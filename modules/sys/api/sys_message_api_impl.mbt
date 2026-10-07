// PluginMessageApi 实现 —— api 层（与 SysQueryApiImpl 同一姿势：委托 service，不写 SQL）。
// 插件在引擎事件监听器里调用，这就是 boot4 WfMessageProcessEventListener 在 moon 栈上的落点
// （hub issues/146 缺口三）。0.1.28 之前做不成这件事：监听器是同步闭包，闭包里 await 不了写库。

///|
pub struct SysMessageApiImpl {
  msg_svc : @svc.MessageServiceImpl[@repo.MessageRepository]
}

///|
pub fn SysMessageApiImpl::make(config : @core.MysqlConfig) -> SysMessageApiImpl {
  { msg_svc: @svc.MessageServiceImpl::{ dao: @repo.MessageRepository::make(config) } }
}

///|
/// ctx：插件调用无请求主体 ⇒ 系统上下文（审计落 NULL，与后台任务同惯例）
fn msg_sys_ctx() -> @core.Ctx {
  @core.Ctx::system()
}

///|
pub impl @api.PluginMessageApi for SysMessageApiImpl with fn send(
  self,
  input : @api.SysMessageInput,
) -> Unit raise @core.MldongError {
  let req : @dto.MessageSaveReq = {
    id: 0L,
    title: input.title,
    content: input.content,
    msg_type: input.msg_type,
    biz_type: input.biz_type,
    biz_id: input.biz_id,
    receiver_user_id: input.receiver_user_id,
    sender_user_id: 0L, // 0＝系统代发（service 里按 ctx 补，插件侧没有登录主体）
    sender_name: Some("系统"),
    url: input.url,
    variable: None,
    is_read: Some(0),
  }
  let _ = self.msg_svc.save(msg_sys_ctx(), req)
}

///|
pub extend SysMessageApiImpl with @api.PluginMessageApi::{send}
