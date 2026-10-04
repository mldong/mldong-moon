// dev_schema MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct SchemaRepository {
  base : BaseDao[@entity.Schema]
}

///|
pub fn SchemaRepository::make(config : @core.MysqlConfig) -> SchemaRepository {
  { base: { config, table: schema_table } }
}

///|
pub impl @dao.SchemaDao for SchemaRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.SchemaDao for SchemaRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.SchemaDao for SchemaRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.SchemaDao for SchemaRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.SchemaDao for SchemaRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.SchemaDao for SchemaRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

pub extend SchemaRepository with @dao.SchemaDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
  find_by_table_name,
  list_by_group_id,
  list_imported_names,
  update_keys,}

// ── 扩展端口实现（直 SQL；行映射复用 schema_table.mbt 的 row_schema）──

///|
let schema_row_mapper : (@moondb.Row) -> @entity.Schema = row_schema

///|
pub impl @dao.SchemaDao for SchemaRepository with fn find_by_table_name(self, table_name) {
  let conn = open_conn(self.base.config)
  let rows = q(
    conn,
    "SELECT * FROM dev_schema WHERE table_name = ? AND is_deleted = 0 ORDER BY id LIMIT 1",
    [@moondb.Text(table_name)],
  )
  conn.close()
  if rows.is_empty() {
    None
  } else {
    Some(schema_row_mapper(rows[0]))
  }
}

///|
pub impl @dao.SchemaDao for SchemaRepository with fn list_by_group_id(self, group_id) {
  let conn = open_conn(self.base.config)
  let rows = q(
    conn,
    "SELECT * FROM dev_schema WHERE schema_group_id = ? AND is_deleted = 0 ORDER BY sort ASC",
    [@moondb.Int64(group_id)],
  )
  conn.close()
  let out : Array[@entity.Schema] = []
  for r in rows {
    out.push(schema_row_mapper(r))
  }
  out
}

///|
pub impl @dao.SchemaDao for SchemaRepository with fn list_imported_names(self) {
  let conn = open_conn(self.base.config)
  let rows = q(
    conn,
    "SELECT table_name FROM dev_schema WHERE is_deleted = 0",
    [],
  )
  conn.close()
  let out : Array[String] = []
  for r in rows {
    out.push(row_text(r, "table_name", ""))
  }
  out
}

///|
pub impl @dao.SchemaDao for SchemaRepository with fn update_keys(self, id, col, keys) {
  // 列名白名单（updateListKeys/updateSearchFormKeys 两个调用方；防注入钉死）
  let safe = if col == "list_keys" || col == "search_form_keys" {
    col
  } else {
    abort("update_keys 列名白名单外: \{col}")
  }
  let conn = open_conn(self.base.config)
  let _ = x(
    conn,
    "UPDATE dev_schema SET \{safe} = ?, update_time = ? WHERE id = ?",
    [@moondb.Text(keys), @moondb.Text(@core.now_str()), @moondb.Int64(id)],
  )
  conn.close()
}

