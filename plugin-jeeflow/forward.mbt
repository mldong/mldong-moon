// Plugin 实现 —— descriptor 趟一（纯数据）+ initialize 趟二（注册全部 /wf/{action} 路由）。
// 每个 action 一个 handler 闭包（捕获各自 action 串），全转发 Facade::flow：
// flow 内部已做 {code,msg,data} 信封与错误转换，handler 直传直返；
// operator（当前人）由登录主体 login_id 注入 args（13 栈 IUserProvider 当前人同位）。

///|
/// 包内 upcast 消费 Plugin impl（装载器经此取 trait object）
pub fn JeeflowPlugin::as_plugin(self : JeeflowPlugin) -> &@api.Plugin {
  self
}

///|
pub extend JeeflowPlugin with @api.Plugin::{descriptor, on_enable, initialize, on_disable}

///|
fn wf_handler(
  facade : @facade.Facade[@jrepo.MysqlRepository, @spi.NoExtRepository],
  action : String,
) -> @mb.Handler {
  @web.wrap(async fn(request) -> Json raise @core.MldongError {
    // body 容错：空 body 当空对象（与 jeeflow demo 同口径），坏 JSON 交 wrap 统一转 99990001
    let body = @web.json_body(request) catch { _ => @jf.empty_object() }
    let args : Map[String, Json] = match body {
      Json::Object(m) => m
      _ => raise @core.MldongError::InvalidInput("body 必须是 JSON 对象")
    }
    let principal = @web.ctx_of(request)
    args["operator"] = @jf.string_of(principal.login_id)
    facade.flow(action, args) catch {
      // flow 出口已转 {code,msg,data} 信封；残余 raise 属未预期形状（async 隐含 Error）
      e => raise @core.MldongError::Internal("jeeflow flow 未预期异常: \{e}")
    }
  })
}

///|
pub impl @api.Plugin for JeeflowPlugin with fn descriptor(
  self : JeeflowPlugin,
) -> @api.PluginDescriptor {
  let _ = self
  jeeflow_descriptor()
}

///|
pub impl @api.Plugin for JeeflowPlugin with fn initialize(
  self : JeeflowPlugin,
  ctx : @api.PluginContext,
) -> Unit raise {
  for a in jeeflow_actions {
    ctx.routes.route("POST", "/wf/\{a}", wf_handler(self.facade, a))
  }
}

///|
pub impl @api.Plugin for JeeflowPlugin with fn on_enable(
  self : JeeflowPlugin,
  ctx : @api.PluginContext,
) -> Unit {
  let _ = self
  let _ = ctx
}

///|
pub impl @api.Plugin for JeeflowPlugin with fn on_disable(
  self : JeeflowPlugin,
  ctx : @api.PluginContext,
) -> Unit raise {
  let _ = self
  let _ = ctx
}
