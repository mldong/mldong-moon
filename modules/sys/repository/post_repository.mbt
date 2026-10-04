// sys_post MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct PostRepository {
  base : BaseDao[@entity.Post]
}

///|
pub fn PostRepository::make(config : @core.MysqlConfig) -> PostRepository {
  { base: { config, table: post_table } }
}

///|
pub impl @dao.PostDao for PostRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.PostDao for PostRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.PostDao for PostRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.PostDao for PostRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.PostDao for PostRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.PostDao for PostRepository with fn check_unique(
  self,
  code,
  exclude_id,
  msg,
) {
  self.base.check_unique("code", S(code), exclude_id, msg)
}

///|
pub impl @dao.PostDao for PostRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}


///|

///|
pub extend PostRepository with @dao.PostDao::{
  insert,
  update,
  remove_by_ids,
  find_by_id,
  find_by_ids,
  page,
  check_unique,
}
