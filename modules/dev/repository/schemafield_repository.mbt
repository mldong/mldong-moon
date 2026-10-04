// dev_schema_field MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct SchemaFieldRepository {
  base : BaseDao[@entity.SchemaField]
}

///|
pub fn SchemaFieldRepository::make(config : @core.MysqlConfig) -> SchemaFieldRepository {
  { base: { config, table: schemafield_table } }
}

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn page(self, w, page_num, page_size) {
  // 默认 sort,id 升序（boot2 page orderByAsc(Sort) 同位）
  self.base.page(w, page_num, page_size, orders=[("sort", false), ("id", false)])
}

pub extend SchemaFieldRepository with @dao.SchemaFieldDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
  list_by_schema_id,
  delete_by_schema_id,
  delete_by_ids,
  replace_schema_fields,
  update_sort_value,}

// ── 扩展端口实现（直 SQL；行映射复用 schemafield_table.mbt 的 row_schemafield）──

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn list_by_schema_id(self, schema_id) {
  let conn = open_conn(self.base.config)
  let rows = q(
    conn,
    "SELECT * FROM dev_schema_field WHERE schema_id = ? AND is_deleted = 0 ORDER BY sort ASC, id ASC",
    [@moondb.Int64(schema_id)],
  )
  conn.close()
  let out : Array[@entity.SchemaField] = []
  for r in rows {
    out.push(row_schemafield(r))
  }
  out
}

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn delete_by_schema_id(self, schema_id) {
  let conn = open_conn(self.base.config)
  let _ = x(conn, "DELETE FROM dev_schema_field WHERE schema_id = ?", [@moondb.Int64(schema_id)])
  conn.close()
}

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn delete_by_ids(self, ids) {
  if ids.is_empty() {
    return
  }
  let conn = open_conn(self.base.config)
  errdefer close_conn(conn)
  for id in ids {
    let _ = x(conn, "DELETE FROM dev_schema_field WHERE id = ?", [@moondb.Int64(id)])
  }
  conn.close()
}


///|
/// 全删重插一个事务收口（updateDesigner）：DELETE by schema_id + 逐行 INSERT
/// （编解码复用 schemafield_table 的 insert_cols，与 BaseDao::insert 同构造）
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn replace_schema_fields(
  self,
  schema_id,
  fields,
) {
  let conn = open_conn(self.base.config)
  errdefer {
    try {
      tx_rollback(conn)
    } catch {
      _ => ()
    }
    close_conn(conn)
  }
  tx_begin(conn)
  let _ = x(conn, "DELETE FROM dev_schema_field WHERE schema_id = ?", [@moondb.Int64(schema_id)])
  for f in fields {
    let pairs : Array[@core.SetPair] = []
    for c in schemafield_table.insert_cols {
      pairs.push(@core.SetPair::{ col: c.name, val: (c.get)(f) })
    }
    let (sql, params) = @core.build_insert("dev_schema_field", pairs)
    let _ = x(conn, sql, to_db_values(params))
  }
  tx_commit(conn)
  conn.close()
}

///|
pub impl @dao.SchemaFieldDao for SchemaFieldRepository with fn update_sort_value(self, id, sort) {
  let conn = open_conn(self.base.config)
  let _ = x(
    conn,
    "UPDATE dev_schema_field SET sort = ?, update_time = ? WHERE id = ?",
    [@moondb.Int64(sort), @moondb.Text(@core.now_str()), @moondb.Int64(id)],
  )
  conn.close()
}
