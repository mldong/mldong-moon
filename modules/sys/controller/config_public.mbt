// sys_config 二次开发扩展 —— /sys/config/public（boot2 同位：@SaIgnore 免鉴权，
// 返回 PUBLIC 前缀配置的 {code: content} map，登录页/版权信息等免登录读）。
// 生成器产物之外的手写扩展面，重生成不覆盖。

///|
/// config 二次开发策略片段（当前无码面——public 端点走全局豁免；预留统一出口）
pub fn config_public_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
}

///|
/// 公开配置端点注册（豁免面路由，走 ctx.post 不经守卫——main 的 exempt 列表须含同路径；
/// 取数闭包由 module.mbt 接线，controller 零 dao-mysql 依赖）
pub fn register_config_public(
  ctx : @mb.ModuleContext,
  list_public : async () -> Array[@entity.Config] raise @core.MldongError,
) -> Unit raise {
  let public_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    // {code: content}——boot2 publicMap 同构（value 只取 content，缺省空串）
    let m : Map[String, Json] = Map([], capacity=0)
    for c in list_public() {
      let _ = m.set(c.code, Json::string(match c.content {
        Some(v) => v
        None => ""
      }))
    }
    @core.ok_data(Json::object(m))
  })
  ctx.post("/sys/config/public", public_handler) catch {
    e => raise e
  }
}
