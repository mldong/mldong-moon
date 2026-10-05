// sys_vis_log MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct VisLogRepository {
  base : BaseDao[@entity.VisLog]
}

///|
pub fn VisLogRepository::make(config : @core.MysqlConfig) -> VisLogRepository {
  { base: { config, table: vislog_table } }
}

///|
pub impl @dao.VisLogDao for VisLogRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.VisLogDao for VisLogRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.VisLogDao for VisLogRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.VisLogDao for VisLogRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.VisLogDao for VisLogRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.VisLogDao for VisLogRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

pub extend VisLogRepository with @dao.VisLogDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
}
