// mldong-moon 装配入口 —— 鉴权（moon-token）+ 模块自注册（每模块一行）
// 起法：export MLDONG_DB_PWD=... && moon run --target wasm cmd/main   （默认 127.0.0.1:18680）
//
// ⚠ TokenAuth 必须在 main 内构造（不能顶层 let）：wasm 档顶层 let 在 __moonbit_init 阶段
//   求值，那时平台熵未装好，opaque_style() 当场 abort（hub moonback 复测报告 §12 实测）。

///|
async fn main raise {
  let config = @core.MysqlConfig::from_env()
  // 鉴权装配（熵依赖运行时，必须在 main 内构造）
  // token_prefix="Bearer"：对齐 mldong 接口契约（sa-token token-prefix + vben5 发 "Bearer <token>"）
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
        .exempt("/sys/getCaptchaOpenFlag"),
      @sys.policy(),
    ),
    @dev.policy(),
  )
  // 关推导：全显式声明，未列端点一律只验登录（个人中心族 boot2 同语义；
  // 推导兜底不用——权限码的最终形状一律写在各 controller 的 policy 片段里）
  policy.by_convention = false
  let g = @mbguard.Guard::new(auth, policy).with_on_error(@web.on_error)

  // 框架级常量 holder：全进程一个实例，sys 灌入 sys_config 并在写路刷新，dev/biz 只读注入
  let holder = @core.ConfigHolder::new()
  // 框架级枚举字典注册中心：全进程一个实例，各模块装配期灌自己的声明（ConfigHolder 同链）
  let enum_registry = @core.EnumDictRegistry::new()
  let root = @mb.Module(ctx => {
    ctx.use_(@sys.install(config, g, auth, holder, enum_registry)) catch {
      _ => abort("sys 模块挂载失败")
    }
    // dev 模块（元数据只读面）
    ctx.use_(@dev.install(config, g)) catch {
      _ => abort("dev 模块挂载失败")
    }
    // 将来新模块各一行：
    // ctx.use_(@biz.module(config, g)) catch { _ => abort("biz 模块挂载失败") }
  })
  let app = @mb.App(root)
  defer app.close()
  let server = @mb.listen(host="127.0.0.1", port=18680)
  println("mldong-moon listening on http://127.0.0.1:18680")
  println("端点：POST /sys/login /sys/logout /sys/refreshToken /sys/getCaptchaOpenFlag + /sys/user/*（含 grantRole） /sys/role|dept|post|config|dict|dictItem/*（带鉴权） /dev/schema/*")
  app.serve(server)
}
