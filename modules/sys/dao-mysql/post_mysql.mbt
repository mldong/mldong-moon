// sys_post MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct PostMysqlDao {
  base : BaseDao[@entity.Post]
}

///|
pub fn PostMysqlDao::make(config : @core.MysqlConfig) -> PostMysqlDao {
  { base: { config, table: post_table } }
}

///|
pub impl @dao.PostDao for PostMysqlDao with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.PostDao for PostMysqlDao with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.PostDao for PostMysqlDao with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.PostDao for PostMysqlDao with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.PostDao for PostMysqlDao with fn find_by_code(self, code) {
  self.base.find_one(@core.where_().eq("code", S(code)))
}

///|
pub impl @dao.PostDao for PostMysqlDao with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

pub extend PostMysqlDao with @dao.PostDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_code,
}
