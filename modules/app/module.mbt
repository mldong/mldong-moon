// app 模块自注册 —— APP 检查升级（UC-0610）：免登录、不查库、转调蒲公英自比较
// buildVersionNo、任何失败降级 data=null 不阻塞 App 启动（家族 13 栈 2026-09-20 对齐，
// 基准 goframe fd88b94；boot2 @SaIgnore + ignoreUrlList 双保险 → moon 豁免面）。

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] install(
  g : @mbguard.Guard[S, P],
) -> @mb.Module {
  @mb.Module(ctx => {
    @ctrl.register(ctx, g)
  })
}

///|
/// app 模块权限策略（check 免登录 → 豁免面）
pub fn policy() -> @guard.RoutePolicy {
  @ctrl.app_policy()
}
