// sys_user 服务 —— 业务逻辑唯一收口（纯规则抽纯函数，IO 编排在方法内）；零 web/ORM 类型

///|
/// 纯规则：用户名/姓名非空与长度（moon_zod 已挡一层，这里守业务口径；测试不连库）
fn validate(req : @dto.UserSaveReq) -> String? {
  if req.user_name.length() < 2 || req.user_name.length() > 32 {
    Some("用户名长度须在 2~32 之间")
  } else if req.real_name.is_empty() {
    Some("姓名不能为空")
  } else {
    None
  }
}

///|
pub(open) trait UserService {
  async fn save(Self, @dto.UserSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @dto.UserSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.User raise @core.MldongError
  async fn page(Self, @dto.UserPageReq) -> (Int, Array[@entity.User]) raise @core.MldongError
}

///|
pub(all) struct UserServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn save(self, req) {
  match validate(req) {
    Some(msg) => raise @core.MldongError::InvalidInput(msg)
    None => ()
  }
  // 业务规则：用户名查重（未删除范围内）
  match self.dao.find_by_user_name(req.user_name) {
    Some(_) => raise @core.MldongError::Conflict("用户名已存在: \{req.user_name}")
    None => ()
  }
  let u : @entity.User = {
    id: @core.next_id(),
    user_name: req.user_name,
    real_name: req.real_name,
    nick_name: req.nick_name,
    avatar: None,
    password: None,
    salt: None,
    mobile_phone: req.mobile_phone,
    tel: req.tel,
    email: req.email,
    admin_type: None,
    sex: req.sex,
    is_locked: Some(0),
    dept_id: req.dept_id,
    post_id: None,
    remark: req.remark,
    create_time: Some(@core.now_str()),
    create_user: None,
    update_time: None,
    update_user: None,
    is_deleted: Some(0),
  }
  self.dao.insert(u)
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn update(self, req) {
  match validate(req) {
    Some(msg) => raise @core.MldongError::InvalidInput(msg)
    None => ()
  }
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("用户不存在: \{req.id}")
    Some(_) => ()
  }
  // 用户名查重（排除自身）
  match self.dao.find_by_user_name(req.user_name) {
    Some(other) => if other.id != req.id {
      raise @core.MldongError::Conflict("用户名已存在: \{req.user_name}")
    }
    None => ()
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let u : @entity.User = {
    id: req.id,
    user_name: req.user_name,
    real_name: req.real_name,
    nick_name: req.nick_name,
    avatar: None,
    password: None,
    salt: None,
    mobile_phone: req.mobile_phone,
    tel: req.tel,
    email: req.email,
    admin_type: None,
    sex: req.sex,
    is_locked: None,
    dept_id: req.dept_id,
    post_id: None,
    remark: req.remark,
    create_time: None,
    create_user: None,
    update_time: None,
    update_user: None,
    is_deleted: None,
  }
  self.dao.update(u)
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn remove_by_ids(self, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn find_by_id(
  self,
  id,
) {
  match self.dao.find_by_id(id) {
    Some(u) => u
    None => raise @core.MldongError::NotFound("用户不存在: \{id}")
  }
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn page(self, req) {
  // 业务决定过滤怎么拼（Wrapper 是 core 的零 ORM 条件组）；m_ 通用件后续另做
  let w = @core.where_()
  if req.user_name is Some(s) {
    let _ = w.like("user_name", s)
  }
  if req.real_name is Some(s) {
    let _ = w.like("real_name", s)
  }
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend UserServiceImpl with UserService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
