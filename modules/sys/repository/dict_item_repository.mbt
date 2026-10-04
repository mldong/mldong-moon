// sys_dict_item MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct DictItemRepository {
  base : BaseDao[@entity.DictItem]
}

///|
pub fn DictItemRepository::make(config : @core.MysqlConfig) -> DictItemRepository {
  { base: { config, table: dictitem_table } }
}

///|
pub impl @dao.DictItemDao for DictItemRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.DictItemDao for DictItemRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.DictItemDao for DictItemRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.DictItemDao for DictItemRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.DictItemDao for DictItemRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.DictItemDao for DictItemRepository with fn check_unique(
  self,
  code,
  exclude_id,
  msg,
) {
  self.base.check_unique("code", S(code), exclude_id, msg)
}

///|
pub impl @dao.DictItemDao for DictItemRepository with fn page(self, w, page_num, page_size, orders) {
  self.base.page(w, page_num, page_size, orders=orders)
}

///|
pub impl @dao.DictItemDao for DictItemRepository with fn list_enabled_by_dict(self, dict_id) {
  self.base.list(@core.where_().eq("dict_id", L(dict_id)).eq("enabled", I(1)), orders=[("sort", false), ("id", false)])
}

///|
pub impl @dao.DictItemDao for DictItemRepository with fn check_unique_in_dict(
  self,
  dict_id,
  code,
  exclude_id,
  msg,
) {
  let w = @core.where_().eq("dict_id", L(dict_id)).eq("code", S(code))
  match exclude_id {
    Some(id) => {
      let _ = w.ne("id", L(id))
    }
    None => ()
  }
  if (self.base.count(w)) > 0 {
    raise @core.MldongError::Conflict(msg)
  }
}

pub extend DictItemRepository with @dao.DictItemDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
  check_unique,
  list_enabled_by_dict,
  check_unique_in_dict,
}
