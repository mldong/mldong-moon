// 审计操作人 —— create_user/update_user 的来源：登录主体 login_id → 用户 id。
// 无 task-local（moonbitlang/async 无 ThreadLocal 对应物，协同式 async 请求在 await 点交错，
// 全局 holder 会跨请求串号）⇒ 审计走显式传参：controller 取（@web.user_id_of）→ service 落库。

///|
/// login_id → 用户 id（兼容旧 "@{appCode}" 复合形态，取 @ 前段；解析失败 None）
pub fn parse_user_id(login_id : String) -> Int64? {
  let id_part = match login_id.split("@").to_array() {
    parts => if parts.length() >= 2 { parts[0].to_owned() } else { login_id }
  }
  if id_part.is_empty() {
    return None
  }
  try {
    Some(@string.parse_int64(id_part))
  } catch {
    _ => None
  }
}
