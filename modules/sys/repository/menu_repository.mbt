// sys_menu MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct MenuRepository {
  base : BaseDao[@entity.Menu]
}

///|
pub fn MenuRepository::make(config : @core.MysqlConfig) -> MenuRepository {
  { base: { config, table: menu_table } }
}

///|
pub impl @dao.MenuDao for MenuRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.MenuDao for MenuRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.MenuDao for MenuRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.MenuDao for MenuRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.MenuDao for MenuRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.MenuDao for MenuRepository with fn check_unique(
  self,
  code,
  exclude_id,
  msg,
) {
  self.base.check_unique("code", S(code), exclude_id, msg)
}

///|
pub impl @dao.MenuDao for MenuRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

///|
pub impl @dao.MenuDao for MenuRepository with fn list_flat(self, w) {
  self.base.list(w, orders=[("sort", false), ("id", false)])
}

///|
pub impl @dao.MenuDao for MenuRepository with fn find_by_app_and_code(self, app_code, code) {
  self.base.find_one(@core.where_().eq("app_code", S(app_code)).eq("code", S(code)))
}

///|
pub impl @dao.MenuDao for MenuRepository with fn list_unsynced_except(self, app_code, exclude_ids) {
  let w = @core.where_().eq("app_code", S(app_code)).eq("is_sync", I(1))
  if !exclude_ids.is_empty() {
    let _ = w.not_in("id", exclude_ids.map(fn(i) { L(i) }))
  }
  self.base.list(w, orders=[("id", false)])
}

pub extend MenuRepository with @dao.MenuDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
  check_unique,
  list_flat,
  find_by_app_and_code,
  list_unsynced_except,
}
