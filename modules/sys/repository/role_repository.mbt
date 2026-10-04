// sys_role MySQL 仓储 —— 薄委托 BaseDao（role 无 join，分页走单表通用路径）

///|
pub(all) struct RoleRepository {
  base : BaseDao[@entity.Role]
}

///|
pub fn RoleRepository::make(config : @core.MysqlConfig) -> RoleRepository {
  { base: { config, table: role_table } }
}

///|
pub impl @dao.RoleDao for RoleRepository with fn insert(self, r) {
  self.base.insert(r)
  r.id
}

///|
pub impl @dao.RoleDao for RoleRepository with fn update(self, r) {
  self.base.update_by_id(r)
}

///|
pub impl @dao.RoleDao for RoleRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.RoleDao for RoleRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.RoleDao for RoleRepository with fn find_by_code(self, code) {
  self.base.find_one(@core.where_().eq("code", S(code)))
}

///|
pub impl @dao.RoleDao for RoleRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

///|

///|

///|
pub extend RoleRepository with @dao.RoleDao::{
  insert,
  update,
  remove_by_ids,
  find_by_id,
  find_by_code,
  page,
}
