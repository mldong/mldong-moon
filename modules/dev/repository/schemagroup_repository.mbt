// dev_schema_group MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct SchemaGroupRepository {
  base : BaseDao[@entity.SchemaGroup]
}

///|
pub fn SchemaGroupRepository::make(config : @core.MysqlConfig) -> SchemaGroupRepository {
  { base: { config, table: schemagroup_table } }
}

///|
pub impl @dao.SchemaGroupDao for SchemaGroupRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.SchemaGroupDao for SchemaGroupRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.SchemaGroupDao for SchemaGroupRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.SchemaGroupDao for SchemaGroupRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.SchemaGroupDao for SchemaGroupRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.SchemaGroupDao for SchemaGroupRepository with fn check_unique(
  self,
  code,
  exclude_id,
  msg,
) {
  self.base.check_unique("code", S(code), exclude_id, msg)
}

///|
pub impl @dao.SchemaGroupDao for SchemaGroupRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

pub extend SchemaGroupRepository with @dao.SchemaGroupDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
  check_unique,
  find_by_code}

// ── 扩展端口实现（直 SQL；行映射复用 schemagroup_table.mbt 的 row_schemagroup）──

///|
pub impl @dao.SchemaGroupDao for SchemaGroupRepository with fn find_by_code(self, code) {
  let conn = open_conn(self.base.config)
  let rows = q(
    conn,
    "SELECT * FROM dev_schema_group WHERE code = ? AND is_deleted = 0 ORDER BY id LIMIT 1",
    [@moondb.Text(code)],
  )
  conn.close()
  if rows.is_empty() {
    None
  } else {
    Some(row_schemagroup(rows[0]))
  }
}

