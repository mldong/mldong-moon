// mldong-moon 装配入口 —— 鉴权（moon-token）+ 模块自注册（每模块一行）
// 起法：export MLDONG_DB_PWD=... && moon run --target wasm cmd/main   （默认 127.0.0.1:18680）
//
// ⚠ TokenAuth 必须在 main 内构造（不能顶层 let）：wasm 档顶层 let 在 __moonbit_init 阶段
//   求值，那时平台熵未装好，opaque_style() 当场 abort（wasm 档真机实测）。

///|
async fn main raise {
  let config = @core.MysqlConfig::from_env()
  // 官方插件注册表（第一插件 = jeeflow-moon；引擎 Facade 进程级一个）
  // 装载器不带 schema 通道（10-09 拍 C）：插件表的 DDL 归 doc/sql/mysql-schema-all.sql，
  // 与 13 栈同法；装卸 = 改 cmd/main/plugins.mbt 注册表 + 重编译 + 重启（MoonBit 无动态加载）。
  let plugins = registry()
  // 在册对账 + 归属闸（合一现读，规则与消息见 plugin-host/reconcile.mbt）：
  //   不一致 = 拒绝启动，消息点名缺/多的是哪些表；
  //   契约前缀白名单（/wf/）= 官方契约插件与 13 栈同一 URL 契约
  // ⚠ wasm 档 abort 的消息不落日志（10-06 实测 run3：只有 RuntimeError 栈）——
  //   拒绝启动的消息必须先 println 再 abort，否则"消息点名"判据测的是空气
  @host.load_check(config, plugins, ["/wf/"]) catch {
    e => {
      println("[plugin-host][fatal] 装载校验失败: \{@core.MldongError::message(e)}")
      abort("装载校验失败")
    }
  }
  // 插件身份指纹（装载校验通过后一行一条）——镜像轮核对"应答确实来自这个代次这套插件"
  // 的现读入口（旧法读 sys_plugin.plugin_version，那张台账表已随 schema 通道撤销）。
  // 插件包不依赖装载器包，契约号直接取 plugin-api 的 SPEC_VERSION。
  for p in plugins {
    let d = p.descriptor()
    println(
      "[plugin-host] 插件 \{d.name} v\{d.plugin_version} spec=\{d.spec_version} tables=\{d.tables.length()}",
    )
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
      let dev_query : &@api.DevQueryApi = @sysapi.DevQueryApiImpl::make(config)
      let msg_api : &@api.PluginMessageApi = @sysapi.SysMessageApiImpl::make(config)
      let pctx = @host.plugin_context(
        config,
        d,
        PluginRouteSink::{ g, mctx: ctx },
        sys_query,
        dev_query,
        dict_sink,
        msg_api,
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
  // 监听端口可配：一键部署包复用的共享前端镜像把 nginx 上游写死成
  //   proxy_pass http://backend:8080（13 栈同此约束），容器内不给 8080 则前端腿整片 502；
  //   本机 dev 缺省仍是 18680。
  let listen_port : UInt16 = match @env.get_env_var("MLDONG_LISTEN_PORT") {
    Some(s) => {
      let v = try {
        @string.parse_int(s)
      } catch {
        _ => 18680
      }
      if v >= 1 && v <= 65535 { v.to_uint16() } else { 18680 }
    }
    None => 18680
  }
  let server = @mb.listen(host=listen_host, port=listen_port)
  println("mldong-moon listening on http://\{listen_host}:\{listen_port}")
  println("端点：POST /sys/login /sys/logout /sys/refreshToken /sys/getCaptchaOpenFlag + /sys/user/*（含 grantRole） /sys/role|dept|post|config|dict|dictItem/*（带鉴权） /dev/schema/*")
  app.serve(server)
}
