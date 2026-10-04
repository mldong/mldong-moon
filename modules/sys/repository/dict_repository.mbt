// sys_dict MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct DictRepository {
  base : BaseDao[@entity.Dict]
}

///|
pub fn DictRepository::make(config : @core.MysqlConfig) -> DictRepository {
  { base: { config, table: dict_table } }
}

///|
pub impl @dao.DictDao for DictRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.DictDao for DictRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.DictDao for DictRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.DictDao for DictRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.DictDao for DictRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.DictDao for DictRepository with fn check_unique(
  self,
  code,
  exclude_id,
  msg,
) {
  self.base.check_unique("code", S(code), exclude_id, msg)
}

///|
pub impl @dao.DictDao for DictRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

///|
pub impl @dao.DictDao for DictRepository with fn find_enabled_by_code(self, code) {
  self.base.find_one(@core.where_().eq("code", S(code)).eq("enabled", I(1)))
}

pub extend DictRepository with @dao.DictDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
  check_unique,
  find_enabled_by_code,
}
