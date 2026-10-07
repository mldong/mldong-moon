// auth_service 单测 —— memory store + stub 供数方（moon-token app 自家测试同范式），
// 冻结时钟覆盖 rotate 兜底分支（操作者原 access 过期、played 会话存活的窗口）。

///|
struct StubRbac {
  by_name : Map[String, @entity.UserAuth]
  by_id : Map[Int64, @entity.UserAuth]
}

///|
impl RbacService for StubRbac with fn find_user_auth_by_name(self, name) {
  self.by_name.get(name)
}

///|
impl RbacService for StubRbac with fn find_user_auth_by_id(self, id) {
  self.by_id.get(id)
}

///|
impl RbacService for StubRbac with fn grant_user_roles(
  self,
  _user_id,
  _role_ids,
) {
  let _ = self
}

///|
impl RbacService for StubRbac with fn grant_role_menus(
  self,
  _role_id,
  _menu_ids,
) {
  let _ = self
}

///|
impl RbacService for StubRbac with fn perm_codes(self, user_id, app_code) {
  let _ = self
  let _ = user_id
  let _ = app_code
  []
}

///|
struct FixedPerms {}

///|
/// 把可能抛错的调用收进 Result（负向断言用；成功分支断 false 即失败）
async fn[T] as_result(f : async () -> T raise @core.MldongError) -> Result[T, @core.MldongError] {
  // Result 必须从此处逃逸（返回值），手工 Ok/Err 包装是文档允许的形态
  let saved : Result[T, @core.MldongError] = Ok(f()) catch { e => Err(e) }
  saved
}

///|
let test_clock : @ref.Ref[Int64] = @ref.Ref::Ref(1_000_000L)

///|
fn make_auth() -> @app.TokenAuth[@mem.MemoryStore, FixedPerms] {
  @port.set_clock(Some(fn() { test_clock.val }))
  let cfg = @app.TokenConfig::default()
  @app.TokenAuth::new(
    "t-auth",
    cfg,
    @mem.MemoryStore::new("t-auth"),
    FixedPerms::{},
    @style.opaque_style(),
  )
}

///|
fn make_user(id : Int64, name : String, locked? : Bool = false, super_admin? : Bool = false) -> @entity.UserAuth {
  let salt = "abc12345"
  @entity.UserAuth::{
    id,
    user_name: name,
    admin_type: if super_admin { Some(1) } else { None },
    is_locked: Some(if locked { 1 } else { 0 }),
    password: Some(@core.md5_hex("pw123" + salt)),
    salt: Some(salt),
  }
}

///|
fn make_rbac(users : Array[@entity.UserAuth]) -> StubRbac {
  let by_name : Map[String, @entity.UserAuth] = Map([], capacity=0)
  let by_id : Map[Int64, @entity.UserAuth] = Map([], capacity=0)
  for u in users {
    by_name.set(u.user_name, u)
    by_id.set(u.id, u)
  }
  StubRbac::{ by_name, by_id }
}

///|
async test "A1 login_by_password 正向：凭证编排 + 签会话" {
  let auth = make_auth()
  let rbac = make_rbac([make_user(1L, "alice")])
  let r = login_by_password(auth, rbac, "alice", "pw123", [("appCode", "platform")])
  assert_eq(r.login_id, "1")
  assert_true(r.token.length() > 0 && r.refresh_token.length() > 0)
}

///|
async test "A2 login_by_password 错密与不存在同话术（防枚举）" {
  let auth = make_auth()
  let rbac = make_rbac([make_user(1L, "alice")])
  match as_result(async fn() raise @core.MldongError { login_by_password(auth, rbac, "alice", "wrong", []) }) {
    Err(e) => assert_eq(e.message(), "用户名或密码错误")
    Ok(_) => assert_true(false)
  }
  match as_result(async fn() raise @core.MldongError { login_by_password(auth, rbac, "ghost", "pw123", []) }) {
    Err(e) => assert_eq(e.message(), "用户名或密码错误")
    Ok(_) => assert_true(false)
  }
}

///|
async test "A3 login_by_password 锁定拒绝" {
  let auth = make_auth()
  let rbac = make_rbac([make_user(1L, "bob", locked=true)])
  match as_result(async fn() raise @core.MldongError { login_by_password(auth, rbac, "bob", "pw123", []) }) {
    Err(e) => assert_eq(e.message(), "用户已锁定")
    Ok(_) => assert_true(false)
  }
}

///|
async test "A4 play 超管守卫：非超管不能扮演超管" {
  let auth = make_auth()
  let rbac = make_rbac([
    make_user(1L, "op"),
    make_user(2L, "boss", super_admin=true),
  ])
  let op = login_by_password(auth, rbac, "op", "pw123", [])
  match as_result(async fn() raise @core.MldongError { play(auth, rbac, "1", op.token, false, 2L, []) }) {
    Err(e) => assert_eq(e.message(), "非超级管理员不能扮演超级管理员")
    Ok(_) => assert_true(false)
  }
}

///|
async test "A5 play 正向：目标身份会话 + extra 盖章 + 操作者会话未动" {
  let auth = make_auth()
  let rbac = make_rbac([
    make_user(1L, "op"),
    make_user(2L, "alice"),
  ])
  let op = login_by_password(auth, rbac, "op", "pw123", [])
  let r = play(auth, rbac, "1", op.token, true, 2L, [("ua", "test-ua")])
  assert_eq(r.login_id, "2")
  let played = auth.read_session(r.token) catch { _ => None }
  match played {
    Some(ss) => {
      assert_eq(ss.login_id(), "2")
      assert_eq(ss.extra("isPlayer"), Some("true"))
      assert_eq(ss.extra("playerToken"), Some(op.token))
      assert_eq(ss.extra("playUserAccount"), Some("op"))
      assert_eq(ss.extra("ua"), Some("test-ua"))
    }
    None => assert_true(false)
  }
  // 操作者会话原封不动
  match (auth.read_session(op.token) catch { _ => None }) {
    Some(ss) => assert_eq(ss.login_id(), "1")
    None => assert_true(false)
  }
}

///|
async test "A6 unplay 正向：回跳操作者原 token + played 会话注销" {
  let auth = make_auth()
  let rbac = make_rbac([
    make_user(1L, "op"),
    make_user(2L, "alice"),
  ])
  let op = login_by_password(auth, rbac, "op", "pw123", [])
  let played = play(auth, rbac, "1", op.token, false, 2L, [])
  let r = unplay(auth, played.token)
  assert_eq(r.token, op.token)
  assert_eq(r.login_id, "1")
  // played 会话已注销
  match (auth.read_session(played.token) catch { _ => None }) {
    Some(_) => assert_true(false)
    None => ()
  }
  // 操作者原会话仍可用
  match (auth.read_session(op.token) catch { _ => None }) {
    Some(ss) => assert_eq(ss.login_id(), "1")
    None => assert_true(false)
  }
}

///|
async test "A7 unplay 非扮演会话拒绝" {
  let auth = make_auth()
  let rbac = make_rbac([make_user(1L, "op")])
  let op = login_by_password(auth, rbac, "op", "pw123", [])
  match as_result(async fn() raise @core.MldongError { unplay(auth, op.token) }) {
    Err(e) => assert_eq(e.message(), "当前会话不是扮演会话")
    Ok(_) => assert_true(false)
  }
}

///|
async test "A8 rotate 兜底：操作者原 access 过期、played 会话存活" {
  let auth = make_auth()
  let rbac = make_rbac([
    make_user(1L, "op"),
    make_user(2L, "alice"),
  ])
  let op = login_by_password(auth, rbac, "op", "pw123", [])
  // 5h 后操作者再扮演（其 access 还剩 1h 寿命）
  test_clock.val = test_clock.val + 5L * 3600L * 1000L
  let played = play(auth, rbac, "1", op.token, false, 2L, [])
  // 再过 2h：操作者原 access 已死（签发后 6h），played 会话仍活（签发后 2h）
  test_clock.val = test_clock.val + 2L * 3600L * 1000L
  // 前置：原 access 确已过期（memory store 对过期活会话仍交回载荷，判活看 expire_at）
  match (auth.read_session(op.token) catch { _ => None }) {
    Some(ss) => assert_true(ss.expire_at() <= test_clock.val)
    None => ()
  }
  let r = unplay(auth, played.token)
  // rotate 兜底签出全新操作者对（≠ 已死的原 token）
  assert_true(r.token != op.token)
  assert_true(r.refresh_token != op.refresh_token)
  match (auth.read_session(r.token) catch { _ => None }) {
    Some(ss) => assert_eq(ss.login_id(), "1")
    None => assert_true(false)
  }
  // played 会话已注销
  match (auth.read_session(played.token) catch { _ => None }) {
    Some(_) => assert_true(false)
    None => ()
  }
  @port.set_clock(None)
}

///|
async test "A9 player_markers_of：非扮演恒 false" {
  assert_eq(player_markers_of(None), (false, ""))
  let auth = make_auth()
  let rbac = make_rbac([make_user(1L, "op")])
  let op = login_by_password(auth, rbac, "op", "pw123", [])
  let ss = auth.read_session(op.token) catch { _ => None }
  assert_eq(player_markers_of(ss), (false, ""))
}
