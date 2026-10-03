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
  async fn page(Self, @dto.UserPageReq) -> (Int, Array[@entity.UserPageRow]) raise @core.MldongError
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
    // 业务默认：普通管理员（boot2 AdminTypeEnum.COMMON_ADMIN）——分页"超管不可见"按 admin_type <> 1
    // 过滤，落 NULL 会因三值逻辑漏行，故 save 必给默认
    admin_type: Some(2),
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
  // 动态条件 service 拼（对齐 boot2 page 语义：列带表别名前缀；Wrapper 是 core 零 ORM 条件组）
  let w = @core.where_()
  let _ = w.eq("t.is_deleted", @core.I(0))
  // 超级管理员不可见（boot2：ne t.admin_type, SUPER_ADMIN(1)）
  let _ = w.ne("t.admin_type", @core.I(1))
  if req.user_name is Some(s) {
    let _ = w.like("t.user_name", s)
  }
  if req.real_name is Some(s) {
    let _ = w.like("t.real_name", s)
  }
  // 关键字：姓名/用户名双列 OR（boot2 keywords 的 apply 片段同款）
  if req.keywords is Some(kw) {
    if !kw.is_empty() {
      let _ = w.raw("(t.real_name like ? or t.user_name like ?)", [@core.S("%\{kw}%"), @core.S("%\{kw}%")])
    }
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
