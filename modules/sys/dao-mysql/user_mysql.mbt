// sys_user MySQL 仓储 —— 业务端口（UserDao）薄实现，全部委托 BaseDao 通用模板；
// 业务特有的查询用 wrapper 组合（怎么用由业务说了算），moondb+moonmysql 只进本包

///|
pub(all) struct UserMysqlDao {
  base : BaseDao[@entity.User]
}

///|
pub fn UserMysqlDao::make(config : MysqlConfig) -> UserMysqlDao {
  { base: { config, table: user_table } }
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn insert(self, u) {
  self.base.insert(u)
  u.id
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn update(self, u) {
  self.base.update_by_id(u)
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn find_by_user_name(self, user_name) {
  self.base.find_one(@core.where_().eq("user_name", S(user_name)))
}

///|
pub extend UserMysqlDao with @dao.UserDao::{
  remove_by_ids,
  find_by_user_name,
  find_by_id,
  insert,
  update,
}
