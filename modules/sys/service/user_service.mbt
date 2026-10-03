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
    create_time: None,
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
  // 先读旧值合并（对齐 MyBatis-Plus updateById 的 null 字段不覆盖语义），NOT NULL 列不误伤
  let cur = match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("用户不存在: \{req.id}")
    Some(cur) => cur
  }
  let u : @entity.User = {
    id: req.id,
    user_name: req.user_name,
    real_name: req.real_name,
    nick_name: if req.nick_name is Some(_) { req.nick_name } else { cur.nick_name },
    avatar: cur.avatar,
    password: cur.password,
    salt: cur.salt,
    mobile_phone: if req.mobile_phone is Some(_) { req.mobile_phone } else { cur.mobile_phone },
    tel: if req.tel is Some(_) { req.tel } else { cur.tel },
    email: if req.email is Some(_) { req.email } else { cur.email },
    admin_type: cur.admin_type,
    sex: if req.sex is Some(_) { req.sex } else { cur.sex },
    is_locked: cur.is_locked,
    dept_id: if req.dept_id is Some(_) { req.dept_id } else { cur.dept_id },
    post_id: cur.post_id,
    remark: if req.remark is Some(_) { req.remark } else { cur.remark },
    create_time: cur.create_time,
    create_user: cur.create_user,
    update_time: None,
    update_user: None,
    is_deleted: cur.is_deleted,
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
  self.dao.page(req)
}

///|
pub extend UserServiceImpl with UserService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
