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
  /// 批量按 id 查（在线列表 join 用户名用，controller 编排 moon-token 枚举时取名称）
  async fn find_by_ids(Self, Array[Int64]) -> Array[@entity.User] raise @core.MldongError
  /// 锁定/解锁（locked=1/0）；返回实际处理条数
  async fn set_locked(Self, Array[Int64], Int) -> Int raise @core.MldongError
  /// 重置为默认密码（新盐 + md5(默认密码+盐)；超管跳过）；返回实际重置条数（boot2 resetPwd 同语义）
  async fn reset_password(Self, Array[Int64]) -> Int raise @core.MldongError
  /// 用户下拉选项（userName/realName LIKE，上限 50）
  async fn select_options(Self, String) -> Array[@entity.User] raise @core.MldongError
  /// 全量轻量用户（部门用户树用；未删除范围）
  async fn list_simple(Self) -> Array[@entity.User] raise @core.MldongError
  /// 修改个人信息（只动 realName/nickName/sex，其余字段忽略；对齐 boot2 ValidInfo 组）
  async fn update_info(Self, @dto.UserSaveReq) -> Unit raise @core.MldongError
  /// 修改个人密码（验旧密 md5(旧+盐)；新盐 + md5(新+盐)；boot2 updatePwd 同语义）
  async fn update_password(Self, Int64, String, String) -> Unit raise @core.MldongError
  /// 修改个人头像（boot2 updateAvatar：avatar 存 URL 串）
  async fn update_avatar(Self, Int64, String) -> Unit raise @core.MldongError
}

///|
pub(all) struct UserServiceImpl[R] {
  dao : R
  /// 默认密码明文取值（boot2 ConstantContextHolder.getDefaultPassword 同位：
  /// 配置 holder/env 优先，缺省 123456——构造方注入，service 不依赖 holder 类型）
  mut default_password_of : () -> String
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
  // 密码机制对齐 boot2 save：不收用户自报密码，发默认密码（holder 可配）+ 8 位随机盐
  let default_password = (self.default_password_of)()
  let salt = @core.random_salt()
  let u : @entity.User = {
    id: @core.next_id(),
    user_name: req.user_name,
    real_name: req.real_name,
    nick_name: req.nick_name,
    avatar: None,
    password: Some(@core.md5_hex(default_password + salt)),
    salt: Some(salt),
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
  // 业务硬条件（对齐 boot2 page 语义）+ m_ 动态条件（通用查询件解析，mldong 框架同约定）
  let w = @core.where_()
  let _ = w.eq("t.is_deleted", @core.I(0))
  // 超级管理员不可见（boot2：ne t.admin_type, SUPER_ADMIN(1)）
  let _ = w.ne("t.admin_type", @core.I(1))
  let _ = w.append(req.m)
  // 关键字：多列 OR 模糊（searchKeys 前端可带表别名；缺省姓名/用户名双列）
  let (kw, keys) = @core.parse_keywords_with_raw(
    req.keywords, req.search_keys,
    default_search_keys=["t.real_name", "t.user_name"],
  )
  if !kw.is_empty() && !keys.is_empty() {
    let ors : Array[String] = []
    let params : Array[@core.SqlValue] = []
    for c in keys {
      ors.push("\{c} like ?")
      params.push(@core.S("%\{kw}%"))
    }
    let _ = w.raw("(\{ors.join(" or ")})", params)
  }
  self.dao.page(w, req.page_num, req.page_size)
}

///|
///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn find_by_ids(self, ids) {
  if ids.is_empty() {
    return []
  }
  self.dao.find_by_ids(ids)
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn set_locked(
  self,
  ids,
  locked,
) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.set_locked(ids, locked)
  ids.length()
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn reset_password(self, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  let mut n = 0
  for id in ids {
    match self.dao.find_by_id(id) {
      // 超管不允许重置（boot2 resetPwd 同过滤）
      Some(u) => if u.admin_type != Some(1) {
        let salt = @core.random_salt()
        self.dao.update_password(id, @core.md5_hex((self.default_password_of)() + salt), salt)
        n = n + 1
      }
      None => ()
    }
  }
  n
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn select_options(self, keywords) {
  self.dao.select_options(keywords)
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn list_simple(self) {
  self.dao.list_simple()
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn update_info(self, req) {
  let old = match self.dao.find_by_id(req.id) {
    Some(u) => u
    None => raise @core.MldongError::NotFound("用户不存在: \{req.id}")
  }
  // 只动个人信息组字段（boot2 ValidInfo：realName/nickName/sex），其余原样保留
  //（real_name 不可变字段，重构整记录提交；update_cols 之外的列本就不写）
  let u : @entity.User = {
    id: old.id,
    user_name: old.user_name,
    real_name: req.real_name,
    nick_name: req.nick_name,
    avatar: old.avatar,
    password: old.password,
    salt: old.salt,
    mobile_phone: old.mobile_phone,
    tel: old.tel,
    email: old.email,
    admin_type: old.admin_type,
    sex: req.sex,
    is_locked: old.is_locked,
    dept_id: old.dept_id,
    post_id: old.post_id,
    remark: old.remark,
    create_time: old.create_time,
    create_user: old.create_user,
    update_time: Some(@core.now_str()),
    update_user: None,
    is_deleted: old.is_deleted,
  }
  self.dao.update(u)
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn update_password(
  self,
  id,
  old_password,
  new_password,
) {
  let u = match self.dao.find_by_id(id) {
    Some(u) => u
    None => raise @core.MldongError::NotFound("用户不存在: \{id}")
  }
  if !@core.password_matches(old_password, u.password, u.salt) {
    raise @core.MldongError::Business("旧密码不正确")
  }
  if new_password.length() < 6 {
    raise @core.MldongError::InvalidInput("新密码长度至少 6 位")
  }
  let salt = @core.random_salt()
  self.dao.update_password(id, @core.md5_hex(new_password + salt), salt)
}

///|
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn update_avatar(
  self,
  id,
  avatar,
) {
  let old = match self.dao.find_by_id(id) {
    Some(u) => u
    None => raise @core.MldongError::NotFound("用户不存在: \{id}")
  }
  let u : @entity.User = {
    id: old.id,
    user_name: old.user_name,
    real_name: old.real_name,
    nick_name: old.nick_name,
    avatar: Some(avatar),
    password: old.password,
    salt: old.salt,
    mobile_phone: old.mobile_phone,
    tel: old.tel,
    email: old.email,
    admin_type: old.admin_type,
    sex: old.sex,
    is_locked: old.is_locked,
    dept_id: old.dept_id,
    post_id: old.post_id,
    remark: old.remark,
    create_time: old.create_time,
    create_user: old.create_user,
    update_time: Some(@core.now_str()),
    update_user: None,
    is_deleted: old.is_deleted,
  }
  self.dao.update(u)
}

pub extend UserServiceImpl with UserService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
  find_by_ids,
  set_locked,
  reset_password,
  select_options,
  update_info,
  update_password,
  update_avatar,
  list_simple,
}
