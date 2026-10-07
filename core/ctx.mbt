// 请求上下文 —— 框架自有（区别于 web 层 Request）：goframe ctx 显式传参同位。
// 为什么显式传而不是全局 holder：moonbitlang/async 无 task-local（ThreadLocal 对应物），
// 协同式 async 请求在 await 点交错，全局可变状态会跨请求串号；Go 社区同理废弃了
// goroutine-local 隐式方案——显式传参是两家共同的选择。
// 服务层只认本类型（core 定义，零 web/零 moon-token 依赖）；装配由 core-web 从登录主体完成。

///|
pub(all) struct Ctx {
  /// 当前登录用户 id（None = 豁免面/系统任务/未登录上下文）
  mut user_id : Int64?
  /// 登录主体原文（login_id；审计与业务展示用）
  mut login_id : String
  /// 应用编码（appCode 会话属性；豁免面 None。TODO：登录端点填入，
  /// guard 面等 moon-token Principal 携带 extra 快照后补）
  mut app_code : String?
}

///|
/// 受保护请求的主体上下文
pub fn Ctx::make(user_id : Int64?, login_id : String) -> Ctx {
  { user_id, login_id, app_code: None }
}

///|
/// 系统上下文（后台任务/豁免面/无主体场景；审计落 NULL）
pub fn Ctx::system() -> Ctx {
  { user_id: None, login_id: "", app_code: None }
}
///|
/// 落库用的应用编码（boot2 MenuServiceImpl/RoleServiceImpl 的
/// `if (StrUtil.isEmpty(param.getAppCode())) entity.setAppCode(LoginUserHolder.getAppCode())`
/// 同位）：入参优先 → 请求域 appCode → platform。入参缺省**不写 NULL**，
/// 否则新建的角色/菜单落不进任何 appCode 域，授权链与菜单树都查不到它。
pub fn Ctx::resolve_app_code(self : Ctx, from_body : String?) -> String {
  let mut out = "platform"
  match self.app_code {
    Some(v) if !v.is_empty() => { out = v }
    _ => ()
  }
  match from_body {
    Some(v) if !v.is_empty() => { out = v }
    _ => ()
  }
  out
}
