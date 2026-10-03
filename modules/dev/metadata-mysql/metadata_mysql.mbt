// MySQL 元数据实现 —— information_schema 直读（SHOW 系不稳参，走标准信息模式）。
// 连接助手与 moon-sys/dao-mysql 各持一份（模板自包含；共享需求成立再抽公共件）。

///|
pub(all) struct MetadataMysqlDao {
  config : @core.MysqlConfig
}

///|
pub fn MetadataMysqlDao::make(config : @core.MysqlConfig) -> MetadataMysqlDao {
  { config: config }
}

///|
async fn open_conn(config : @core.MysqlConfig) -> @client.MysqlConn raise @core.MldongError {
  try {
    @client.MysqlConn::connect(config.host, config.port, config.user, config.password, config.database)
  } catch {
    e => raise @core.MldongError::Internal("metadata mysql connect: \{e}")
  }
}

///|
async fn q(
  conn : @client.MysqlConn,
  sql : String,
  params : Array[@moondb.Value],
) -> Array[@moondb.Row] raise @core.MldongError {
  try {
    conn.query(sql, params)
  } catch {
    e => raise @core.MldongError::Internal("metadata mysql query: \{e}")
  }
}

///|
fn value_to_text(v : @moondb.Value) -> String? {
  match v {
    Null => None
    Text(s) => Some(s)
    Int64(n) => Some(n.to_string())
    Int(n) => Some(n.to_string())
    Double(d) => Some(d.to_string())
    Bool(b) => Some(if b { "1" } else { "0" })
    Blob(_) => None
  }
}

///|
fn row_text(r : @moondb.Row, col : String, default : String) -> String {
  match r.by_name(col) {
    Some(v) =>
      match value_to_text(v) {
        Some(s) => s
        None => default
      }
    None => default
  }
}

///|
fn row_opt_text(r : @moondb.Row, col : String) -> String? {
  match r.by_name(col) {
    Some(v) => value_to_text(v)
    None => None
  }
}

///|
pub impl @meta.MetadataDao for MetadataMysqlDao with fn list_tables(self, keywords) {
  let conn = open_conn(self.config)
  let base = "SELECT table_name, table_comment FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'"
  let (sql, params) = if keywords.is_empty() {
    ("\{base} ORDER BY table_name", ([] : Array[@moondb.Value]))
  } else {
    let pat = "%\{keywords}%"
    (
      "\{base} AND (table_name LIKE ? OR table_comment LIKE ?) ORDER BY table_name",
      [@moondb.Text(pat), @moondb.Text(pat)],
    )
  }
  let rows = q(conn, sql, params)
  conn.close()
  let out : Array[@meta.TableMeta] = []
  for r in rows {
    out.push({
      name: row_text(r, "table_name", ""),
      comment: row_text(r, "table_comment", ""),
    })
  }
  out
}

///|
pub impl @meta.MetadataDao for MetadataMysqlDao with fn list_columns(self, table) {
  let conn = open_conn(self.config)
  let rows = q(
    conn,
    "SELECT column_name, data_type, column_type, is_nullable, column_default, column_comment, column_key, extra FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? ORDER BY ordinal_position",
    [@moondb.Text(table)],
  )
  conn.close()
  let out : Array[@meta.ColumnMeta] = []
  for r in rows {
    out.push({
      name: row_text(r, "column_name", ""),
      data_type: row_text(r, "data_type", ""),
      column_type: row_text(r, "column_type", ""),
      is_nullable: row_text(r, "is_nullable", "NO"),
      default_value: row_opt_text(r, "column_default"),
      comment: row_text(r, "column_comment", ""),
      is_pk: row_text(r, "column_key", "") == "PRI",
      extra: row_text(r, "extra", ""),
    })
  }
  out
}
