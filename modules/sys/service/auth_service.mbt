// 认证域服务 —— boot2 AuthServiceImpl 同位（登录凭证编排 + 扮演往返）。
// moon-token 的 TokenAuth 已吸收"会话管理"本体（签发/轮转/注销/踢人是它的公开原语），
// 这里只收业务编排：凭证校验、超管守卫、扮演 extra 盖章、回跳决策——
// 全部走 TokenAuth 公开 API 零源码改动；HTTP 解析与信封留在 controller。

///|
pub(all) struct PlayResult {
  token : String
  refresh_token : String
  /// 被扮演者 id 字符串（= 新会话 login_id，前端据此切换身份）
  login_id : String
}

///|
pub(all) struct UnPlayResult {
  /// 回跳用的操作者 token（或 rotate 兜底签出的新 token）
  token : String
  refresh_token : String
  /// 操作者 id 字符串（会话 extra 的 playerUserId）
  login_id : String
}

///|
/// 登录凭证编排（boot2 login 同位）：存在性 → 锁定 → md5(密码+盐) → 签会话。
/// 失败统一 Business——controller 侧 catch 后走 fail_auth 转 99990401 信封
/// （错密与不存在同话术防枚举，boot2 同设计）。
pub async fn[S : @port.TokenStore, P, R : RbacService] login_by_password(
  auth : @app.TokenAuth[S, P],
  rbac : R,
  user_name : String,
  password : String,
  /// 登录会话属性（appCode/ip/ua，controller 从请求事实提取）
  client_kvs : Array[(String, String)],
) -> @app.LoginResult raise @core.MldongError {
  let ua = rbac.find_user_auth_by_name(user_name)
  let ua = match ua {
    None => raise @core.MldongError::Business("用户名或密码错误")
    Some(u) => u
  }
  if ua.is_locked == Some(1) {
    raise @core.MldongError::Business("用户已锁定")
  }
  if !@core.password_matches(password, ua.password, ua.salt) {
    raise @core.MldongError::Business("用户名或密码错误")
  }
  let extra : Map[String, String] = Map::from_iter(client_kvs.iter())
  auth.login(ua.id.to_string(), device="pc", extra=Some(extra)) catch {
    err => raise @core.MldongError::Internal(err.message())
  }
}

///|
/// 扮演（boot2 AuthServiceImpl.playUser 双会话同构）：目标存在性 + 超管守卫 →
/// 给目标签真会话，extra 盖操作者标记（isPlayer/playerToken/playerUserId/
/// playUserAccount + playerRefreshToken 兜底）；操作者会话原封不动——
/// moon-token Coexist 策略不踢目标既有登录，权限快照 per-token 天然按目标解析。
pub async fn[S : @port.TokenStore, P, R : RbacService] play(
  auth : @app.TokenAuth[S, P],
  rbac : R,
  operator_login_id : String,
  operator_token : String,
  operator_super : Bool,
  target_id : Int64,
  /// 客户端事实继承（ip/ua，controller 从请求提取；在线列表审计口径）
  client_kvs : Array[(String, String)],
) -> PlayResult raise @core.MldongError {
  if target_id == 0L {
    raise @core.MldongError::InvalidInput("userId不能为空")
  }
  let target = rbac.find_user_auth_by_id(target_id)
  let target = match target {
    None => raise @core.MldongError::NotFound("用户不存在: \{target_id}")
    Some(ua) => ua
  }
  if target.admin_type == Some(1) && !operator_super {
    raise @core.MldongError::Business("非超级管理员不能扮演超级管理员")
  }
  let operator_id = parse_user_id(operator_login_id).unwrap_or(0L)
  let operator_account = match rbac.find_user_auth_by_id(operator_id) {
    Some(op) => op.user_name
    None => ""
  }
  let op_session = auth.read_session(operator_token) catch {
    _ => None
  }
  let kvs : Array[(String, String)] = [
    ("isPlayer", "true"),
    ("playerToken", operator_token),
    ("playerUserId", operator_login_id),
    ("playUserAccount", operator_account),
    (
      "playerRefreshToken",
      // moon 特有兜底：操作者原 access 2h 滑动过期后，unPlay 靠它 rotate 换全新对
      // （boot2 sa-token token 长活无此步）
      match op_session {
        Some(ss) => ss.refresh_token()
        None => ""
      },
    ),
    (
      "appCode",
      match op_session {
        Some(ss) => ss.extra("appCode").unwrap_or("platform")
        None => "platform"
      },
    ),
  ]
  for kv in client_kvs {
    kvs.push(kv)
  }
  let extra : Map[String, String] = Map::from_iter(kvs.iter())
  let result = auth.login(target_id.to_string(), device="pc", extra=Some(extra)) catch {
    err => raise @core.MldongError::Internal(err.message())
  }
  PlayResult::{
    token: result.token,
    refresh_token: result.refresh_token,
    login_id: result.login_id,
  }
}

///|
/// 退出扮演（boot2 unPlayUser 同构）：登出 played 会话，凭会话 extra 的操作者
/// token 回跳；原 access 已过期走 playerRefreshToken rotate 兜底（全量轮转换新对）。
/// 非扮演会话/登录失效均 Business 拒绝（boot2 对此返回空 LoginToken，moon 诚实报错）。
pub async fn[S : @port.TokenStore, P] unplay(
  auth : @app.TokenAuth[S, P],
  token : String,
) -> UnPlayResult raise @core.MldongError {
  let ss = auth.read_session(token) catch {
    _ => None
  }
  let player_token = match ss {
    None => raise @core.MldongError::Business("登录状态已失效")
    Some(s) =>
      match s.extra("playerToken") {
        Some(t) if !t.is_empty() => t
        _ => raise @core.MldongError::Business("当前会话不是扮演会话")
      }
  }
  let player_user_id = match ss {
    Some(s) => s.extra("playerUserId").unwrap_or("")
    None => ""
  }
  let origin = auth.read_session(player_token) catch {
    _ => None
  }
  match origin {
    // 原会话仍活（未到 expire_at 且 Active）：直接回跳
    Some(origin_session) =>
      if origin_session.expire_at() > @port.now_ms() {
        auth.logout(token) catch {
          err => raise @core.MldongError::Internal(err.message())
        }
        UnPlayResult::{
          token: player_token,
          refresh_token: origin_session.refresh_token(),
          login_id: player_user_id,
        }
      } else if !(origin_session.status() is @port.Active) {
        // 被踢/被顶的墓碑：不允许借 rotate 绕过强制下线，诚实要求重登
        raise @core.MldongError::Business("登录状态已失效，请重新登录")
      } else {
        // 良性过期：rotate 保底（全量轮转换全新对；extra 随转）
        unplay_rotate(auth, token, ss, player_user_id)
      }
    // 键已回收（登出后 refresh 同删，rotate 自然失败 → 诚实报错；
    // 长期过期的良性场景 refresh 仍活 → rotate 成功）
    None => unplay_rotate(auth, token, ss, player_user_id)
  }
}

///|
/// rotate 兜底：用扮演时保存的操作者 refreshToken 换全新对，并登出 played 会话
async fn[S : @port.TokenStore, P] unplay_rotate(
  auth : @app.TokenAuth[S, P],
  played_token : String,
  ss : @domain.TokenSession?,
  player_user_id : String,
) -> UnPlayResult raise @core.MldongError {
  let prt = match ss {
    Some(s) => s.extra("playerRefreshToken").unwrap_or("")
    None => ""
  }
  if prt.is_empty() {
    raise @core.MldongError::Business("登录状态已失效，请重新登录")
  }
  let r = auth.rotate(prt) catch {
    _ => raise @core.MldongError::Business("登录状态已失效，请重新登录")
  }
  auth.logout(played_token) catch {
    _ => ()
  }
  UnPlayResult::{
    token: r.token,
    refresh_token: r.refresh_token,
    login_id: player_user_id,
  }
}

///|
/// 会话的扮演标记投影：(isPlayer, playUserAccount)。
/// 消费方：/sys/user/info 的 ext 字段（vben5 退出扮演入口开关）+
/// 未来 op_log 切面的 play_user_account 列；非扮演会话/无会话恒 (false, "")。
pub fn player_markers_of(session : @domain.TokenSession?) -> (Bool, String) {
  match session {
    Some(ss) => {
      let is_player = ss.extra("isPlayer").unwrap_or("") == "true"
      let account = if is_player {
        ss.extra("playUserAccount").unwrap_or("")
      } else {
        ""
      }
      (is_player, account)
    }
    None => (false, "")
  }
}
