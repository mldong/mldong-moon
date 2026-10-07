// mldong-moon 装配入口 —— 鉴权（moon-token）+ 模块自注册（每模块一行）
// 起法：export MLDONG_DB_PWD=... && moon run --target wasm cmd/main   （默认 127.0.0.1:18680）
//
// ⚠ TokenAuth 必须在 main 内构造（不能顶层 let）：wasm 档顶层 let 在 __moonbit_init 阶段
//   求值，那时平台熵未装好，opaque_style() 当场 abort（wasm 档真机实测）。

///|
async fn main raise {
  let config = @core.MysqlConfig::from_env()
  // ② 基线增量（先于鉴权/模块装配——插件的 DDL 可能依赖框架的新列，
  //   且清单必须在 Guard 前被读到）：__framework__ 从
  //   MLDONG_MIGRATIONS_DIR（默认 doc/sql/migrations，相对启动 cwd）装载并应用；
  //   失败 = 拒绝启动，消息含组名 + version + 驱动原文
  let migrations_dir = match @env.get_env_var("MLDONG_MIGRATIONS_DIR") {
    Some(v) => if v.is_empty() { "doc/sql/migrations" } else { v }
    None => "doc/sql/migrations"
  }
  let fw_group = @host.framework_group(migrations_dir) catch {
    e => {
      // ⚠ wasm 档 abort 的消息不落日志（10-06 实测 run3：只有 RuntimeError 栈）——
      //   拒绝启动的消息必须先 println 再 abort，否则"消息点名"判据测的是空气
      println("[plugin-host][fatal] 基线增量装载失败: \{@core.MldongError::message(e)}")
      abort("基线增量装载失败")
    }
  }
  // 官方插件注册表（第一插件 = jeeflow-moon；引擎 Facade 进程级一个）
  let plugins = registry()
  let groups : Array[@host.MigrationGroup] = [fw_group]
  for p in plugins {
    groups.push(@host.descriptor_group(p.descriptor()))
  }
  @host.apply_all(config, groups) catch {
    e => {
      println("[plugin-host][fatal] 基线增量应用失败: \{@core.MldongError::message(e)}")
      abort("基线增量应用失败")
    }
  }
  // 三方对账 + 归属闸（合一现读，规则与消息见 plugin-host/reconcile.mbt）：
  //   不一致 = 拒绝启动，消息点名缺/多的是哪一方、哪些表；
  //   契约前缀白名单（/wf/）= 官方契约插件与 13 栈同一 URL 契约
  let mut fw_max = 0
  for m in fw_group.migrations {
    if m.version > fw_max {
      fw_max = m.version
    }
  }
  @host.load_check(config, plugins, fw_max, ["/wf/"]) catch {
    e => {
      println("[plugin-host][fatal] 装载校验失败: \{@core.MldongError::message(e)}")
      abort("装载校验失败")
    }
  }
  // 鉴权装配（熵依赖运行时，必须在 main 内构造）
  // token_prefix="Bearer"：对齐 mldong 接口契约（token-prefix 头约定 + vben5 发 "Bearer <token>"）
  // 供数方 = sys 模块的 RBAC 真实现（码链走库：user_role → role_menu → menu.code）
  let token_cfg = @app.TokenConfig::default()
  token_cfg.token_prefix = "Bearer"
  let auth = @app.TokenAuth::new(
    "user",
    token_cfg,
    @mem.MemoryStore::new("user"),
    @sys.rbac_provider(config),
    @style.opaque_style(),
  )
  // 总策略 = 全局豁免面（登录/注销/刷新）+ 各模块 policy 片段聚合
  let policy = @web.merge_policy(
    @web.merge_policy(
      @guard.RoutePolicy::new()
        .exempt("/sys/login")
        .exempt("/sys/logout")
        .exempt("/sys/refreshToken")
        .exempt("/sys/getCaptchaOpenFlag")
        .exempt("/sys/captcha")
        .exempt("/sys/getSm2PublicKey")
        .exempt("/sys/sms/sendCode")
        .exempt("/sys/sms/verifyCode"),
      @sys.policy(),
    ),
    @web.merge_policy(@web.merge_policy(@dev.policy(), @appmod.policy()), plugin_policy(plugins)),
  )
  // 关推导：全显式声明，未列端点一律只验登录（个人中心族 boot2 同语义；
  // 推导兜底不用——权限码的最终形状一律写在各 controller 的 policy 片段里）
  policy.by_convention = false
  let g = @mbguard.Guard::new(auth, policy).with_on_error(@web.on_error)

  // 框架级常量 holder：全进程一个实例，sys 灌入 sys_config 并在写路刷新，dev/biz 只读注入
  let holder = @core.ConfigHolder::new()
  // 框架级枚举字典注册中心：全进程一个实例，各模块装配期灌自己的声明（ConfigHolder 同链）
  let enum_registry = @core.EnumDictRegistry::new()
  // 插件字典贡献面的落点（UC-0432）：declare 走活数组、answer_only 走枚举注册中心
  let dict_sink = @host.FrameworkDictSink::new(enum_registry)
  let root = @mb.Module(ctx => {
    ctx.use_(@sys.install(config, g, auth, holder, enum_registry, [fn() { dict_sink.list_declared() }])) catch {
      _ => abort("sys 模块挂载失败")
    }
    // dev 模块（元数据只读面）
    ctx.use_(@dev.install(config, g, holder, enum_registry, auth)) catch {
      _ => abort("dev 模块挂载失败")
    }
    // app 模块（APP 检查升级，UC-0610 免登录）
    ctx.use_(@appmod.install(g)) catch {
      _ => abort("app 模块挂载失败")
    }
    // 官方插件挂载：PluginContext（ScopedDb + 路由 sink + system Ctx）→ initialize
    //   路由经 guard 注册（鉴权/权限码与框架自有端点零差别），policy 片段已在 Guard 前合入
    for p in plugins {
      let d = p.descriptor()
      let sys_query : &@api.SysQueryApi = @sysapi.SysQueryApiImpl::make(config)
      let pctx = @host.plugin_context(
        config,
        d,
        PluginRouteSink::{ g, mctx: ctx },
        sys_query,
        dict_sink,
      ) catch {
        e => abort("插件 \{d.name} 装载失败: \{@core.MldongError::message(e)}")
      }
      p.initialize(pctx) catch {
        e => abort("插件 \{d.name} initialize 失败: \{e}")
      }
    }
    // 将来新模块各一行：
    // ctx.use_(@biz.module(config, g)) catch { _ => abort("biz 模块挂载失败") }
  })
  let app = @mb.App(root)
  defer app.close()
  // 监听地址可配（容器/镜像形态须 0.0.0.0 才能被端口映射到；本机 dev 默认 127.0.0.1）
  let listen_host = match @env.get_env_var("MLDONG_LISTEN_HOST") {
    Some(v) => if v.is_empty() { "127.0.0.1" } else { v }
    None => "127.0.0.1"
  }
  let server = @mb.listen(host=listen_host, port=18680)
  println("mldong-moon listening on http://127.0.0.1:18680")
  println("端点：POST /sys/login /sys/logout /sys/refreshToken /sys/getCaptchaOpenFlag + /sys/user/*（含 grantRole） /sys/role|dept|post|config|dict|dictItem/*（带鉴权） /dev/schema/*")
  app.serve(server)
}
