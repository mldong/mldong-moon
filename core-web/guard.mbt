// moon-token 集成工具 —— 权限码模块化收集与 mldong 信封失败响应
//
// 收集模式（对齐 boot2 权限注解位置）：权限码声明在端点旁——
// 各实体 controller 导出 policy() 片段（显式 rule 例外 + 豁免，与端点同文件维护），
// 模块聚合、main 合并进总 policy 后交 Guard；推导（derive_perm）只作兜底，
// URL 与权限码不一致的场景（如 boot2 /sys/user/locked 双码 OR）一律显式 rule 表达。

///|
/// 合并权限策略片段：把 part 的豁免面与例外清单并进 total（AND 语义追加）。
/// 各模块各实体各产一片，main 聚合——RoutePolicy 字段 pub(all)，直接搬运。
pub fn merge_policy(total : @guard.RoutePolicy, part : @guard.RoutePolicy) -> @guard.RoutePolicy {
  for e in part.exempt {
    let _ = total.exempt(e)
  }
  for r in part.rules {
    let _ = total.rule(r)
  }
  total
}

///|
/// mldong 风格的鉴权失败响应：**HTTP 恒 200**，业务码进信封（boot2 GlobalExceptionHandler
/// 返回 CommonResult / goframe WriteJson(base.Fail(...)) 同约定——vben5 按 code 分支不走 HTTP 状态），
/// HTTP 200 + 精确码：token 无效/未登录 99990403、无权限码 99990406、参数错 99990001（99990401 只归登录密码错），msg 取 TokenError 精确原因。
/// 经 Guard::with_on_error 挂上，替换 moon-token 默认的空体响应。
pub async fn on_error(
  _request : @mb.Request,
  responder : @mb.Responder,
  err : @port.TokenError,
) -> Unit {
  let status = @mbguard.status_of(err)
  // 受保护端点的 token 校验失败一律 99990403（boot2 NotLoginException→TOKEN_NOT_EXIST、
  // goframe middleware WriteJson(99990403) 同码；99990401 只归登录端点「用户名或密码错误」）。
  // 无权限单独走 99990406（boot2 AuthErrEnum.NO_RESOURCE_AUTH 同码；契约 00-全局约定 表里
  // 99990403 只表示 token 无效/未登录）。原记台账差异"moon 暂同 99990403"由 base-verify L3
  // B03/B05/B06/B14 四组量出，10-07 收口：msg 仍取精确原因（moon 既有惯例，不改文案只改码值）。
  let code = match status {
    401 => 99990403
    403 => 99990406
    400 => 99990001
    _ => 99990000
  }
  let body : Json = { "code": code, "msg": err.message(), "data": Json::null() }
  responder.send_json(body, headers=[("Content-Type", "application/json; charset=utf-8")]) catch {
    _ => ()
  }
}

///|
/// 从请求取 token（头优先、同名 cookie 兜底），并剥 "Bearer " 前缀——
/// 与 TokenConfig.token_prefix 同一约定（mldong 框架：token-prefix 头约定 + vben5 发 "Bearer <token>"）。
/// 豁免面端点（登录/注销）不走 guard 的 extract_token，手取头时必须用本函数对齐，
/// 否则拿到带前缀的串查不到会话且 logout 幂等不报错（静默失效，已踩）。
pub fn token_of(request : @mb.Request) -> String {
  let raw = match request.headers.get("Authorization") {
    None => ""
    Some(v) => v.to_owned()
  }
  let from_header = if raw.has_prefix("Bearer ") {
    raw[7:].to_owned()
  } else {
    raw
  }
  if from_header.is_empty() {
    match request.cookie().get("Authorization") {
      None => ""
      Some(v) => v
    }
  } else {
    from_header
  }
}

///|
/// 当前请求的框架上下文（service 层第一参）：登录主体 → Ctx；
/// 豁免面/无主体 = Ctx::system()（审计落 NULL，不报错）。
pub fn ctx_of(request : @mb.Request) -> @core.Ctx {
  let ctx = match @mbguard.principal_of(request) {
    Some(p) => @core.Ctx::make(@core.parse_user_id(p.login_id), p.login_id)
    None => @core.Ctx::system()
  }
  // appCode 请求域（boot2 LoginUserHolder.getAppCode 同位）：头缺省 platform——
  // 菜单树/路由菜单/路由同步按域过滤都从这读；vben5 拦截器每请求都带 appCode 头
  ctx.app_code = match request.headers.get("appCode") {
    Some(v) =>
      if v.is_empty() {
        Some("platform")
      } else {
        Some(v.to_owned())
      }
    None => Some("platform")
  }
  ctx
}
