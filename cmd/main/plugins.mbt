// 插件注册表 + 挂载机件 —— 代码方事实（编译进去的就是事实）。
// 官方插件在此登记；装卸 = 改本文件 + 重编译 + 重启（MoonBit 无动态加载，
// 宣称热插拔而做不到是这类机制最毁信任的坑，文档必须明写边界）。
// 第一官方插件 = jeeflow-moon（工作流引擎插件，不走 base+1 集成壳）。

///|
/// 注册表（装配期构造引擎 Facade；MLDONG_DB_* 同一库）
pub fn registry() -> Array[&@api.Plugin] {
  [@jeeflow.JeeflowPlugin::make()]
}

///|
/// 插件 policy 片段：public → exempt、带 perms → 显式 rule（主仓全显式语义不动；
/// 空 perms 路由 = 仅登录，与框架未列端点同语义）。
/// 多码语义由声明方带（`perm_or`）——工作流族 13 栈用的是 boot3 `checkPermissionOr`，
/// 而 guard 的 `RouteRule::make` 默认 And，不带上就会把"任一即可"做成"全都要"。
pub fn plugin_policy(plugins : Array[&@api.Plugin]) -> @guard.RoutePolicy {
  let mut p = @guard.RoutePolicy::new()
  for pl in plugins {
    let d = pl.descriptor()
    for r in d.routes {
      if r.public {
        p = p.exempt(r.path)
      } else if !r.perms.is_empty() {
        let rule = @guard.RouteRule::make(r.path, r.perms)
        p = p.rule(
          if r.perm_or { rule.with_perm_mode(@port.Or) } else { rule },
        )
      }
    }
  }
  p
}

///|
/// 路由 sink：把插件 initialize 里声明的路由经 guard 挂进 moonback
/// （鉴权/权限码走主仓同一条链，与框架自有端点零差别）
pub(all) struct PluginRouteSink[S, P] {
  g : @mbguard.Guard[S, P]
  mctx : @mb.ModuleContext
}

///|
impl[S : @port.TokenStore, P : @port.PermissionProvider] @api.PluginRoutes for PluginRouteSink[S, P] with fn route(
  self : PluginRouteSink[S, P],
  http_method : String,
  path : String,
  handler : @mb.Handler,
) -> Unit raise @core.MldongError {
  if http_method != "POST" {
    raise @core.MldongError::InvalidInput("插件路由 v1 仅支持 POST（契约面全 POST）：\{http_method} \{path}")
  }
  self.g.post(self.mctx, path, handler) catch {
    RouteConflict(path=conflict) =>
      raise @core.MldongError::Conflict("插件路由注册冲突: \{path}（\{conflict}）")
  }
}
