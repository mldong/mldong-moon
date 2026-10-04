// sys_user MySQL 仓储 —— 业务端口（UserDao）薄实现，全部委托 BaseDao 通用模板；
// 业务特有的查询用 wrapper 组合（怎么用由业务说了算），moondb+moonmysql 只进本包

///|
pub(all) struct UserRepository {
  base : BaseDao[@entity.User]
}

///|
pub fn UserRepository::make(config : @core.MysqlConfig) -> UserRepository {
  { base: { config, table: user_table } }
}

///|
pub impl @dao.UserDao for UserRepository with fn insert(self, u) {
  self.base.insert(u)
  u.id
}

///|
pub impl @dao.UserDao for UserRepository with fn update(self, u) {
  self.base.update_by_id(u)
}

///|
pub impl @dao.UserDao for UserRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.UserDao for UserRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.UserDao for UserRepository with fn find_by_user_name(self, user_name) {
  self.base.find_one(@core.where_().eq("user_name", S(user_name)))
}

///|
///|
pub impl @dao.UserDao for UserRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  let (sql, params) = @core.build_select(
    "sys_user",
    self.base.table.cols,
    self.base.base_where().in_("id", vals),
  )
  let out : Array[@entity.User] = []
  for r in self.base.query(sql, params) {
    out.push((self.base.table.from_row)(r))
  }
  out
}

///|
pub impl @dao.UserDao for UserRepository with fn set_locked(self, ids, locked) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  let w = @core.where_().in_("id", vals)
  let _ = w.eq("is_deleted", @core.I(0))
  let (sql, params) = @core.build_update(
    "sys_user",
    [
      @core.SetPair::{ col: "is_locked", val: @core.I(locked) },
      @core.SetPair::{ col: "update_time", val: S(@core.now_str()) },
    ],
    w,
  )
  let _ = self.base.exec(sql, params)
}

///|
pub impl @dao.UserDao for UserRepository with fn update_password(
  self,
  id,
  password,
  salt,
) {
  let (sql, params) = @core.build_update(
    "sys_user",
    [
      @core.SetPair::{ col: "password", val: S(password) },
      @core.SetPair::{ col: "salt", val: S(salt) },
      @core.SetPair::{ col: "update_time", val: S(@core.now_str()) },
    ],
    @core.where_().eq("id", L(id)),
  )
  let _ = self.base.exec(sql, params)
}

///|
pub impl @dao.UserDao for UserRepository with fn select_options(self, keywords) {
  let w = self.base.base_where()
  if !keywords.is_empty() {
    let pat = "%\{keywords}%"
    let _ = w.raw("(user_name like ? or real_name like ?)", [S(pat), S(pat)])
  }
  let (sql, params) = @core.build_select(
    "sys_user",
    ["id", "user_name", "real_name"],
    w,
    orders=[("create_time", true)],
    limit=50,
  )
  let out : Array[@entity.User] = []
  for r in self.base.query(sql, params) {
    out.push((self.base.table.from_row)(r))
  }
  out
}

///|
pub impl @dao.UserDao for UserRepository with fn list_simple(self) {
  let (sql, params) = @core.build_select(
    "sys_user",
    ["id", "dept_id", "real_name", "admin_type"],
    self.base.base_where(),
    orders=[("id", false)],
  )
  let out : Array[@entity.User] = []
  for r in self.base.query(sql, params) {
    out.push((self.base.table.from_row)(r))
  }
  out
}

pub extend UserRepository with @dao.UserDao::{
  remove_by_ids,
  find_by_user_name,
  find_by_id,
  insert,
  update,
  find_by_ids,
  set_locked,
  update_password,
  select_options,
  list_simple,
}
