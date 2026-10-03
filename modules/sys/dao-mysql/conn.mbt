// MySQL 连接与行读取助手 —— 形状照抄 jeeflow-moon repository-mysql（先例：每操作连接即取即用，
// autocommit；凭据只走 MLDONG_DB_* env，默认值不含密码）

///|
/// 建立连接（配置结构在 core；连接动作依赖 moonmysql 驱动，只进本层）
async fn open_conn(config : @core.MysqlConfig) -> @client.MysqlConn raise @core.MldongError {
  try {
    @client.MysqlConn::connect(config.host, config.port, config.user, config.password, config.database)
  } catch {
    e => raise @core.MldongError::Internal("mysql connect: \{e}")
  }
}

///|
/// query 归一助手
pub async fn q(
  conn : @client.MysqlConn,
  sql : String,
  params : Array[@moondb.Value]
) -> Array[@moondb.Row] raise @core.MldongError {
  try {
    conn.query(sql, params)
  } catch {
    e => raise @core.MldongError::Internal("mysql query: \{e}")
  }
}

///|
/// execute 归一助手
pub async fn x(
  conn : @client.MysqlConn,
  sql : String,
  params : Array[@moondb.Value]
) -> @moondb.ExecResult raise @core.MldongError {
  try {
    conn.execute(sql, params)
  } catch {
    e => raise @core.MldongError::Internal("mysql execute: \{e}")
  }
}

// ── Row NULL 安全读取器（NULL→零值；DATETIME 走文本截 19 位）——抄 jeeflow-moon ──

///|
fn value_to_text(v : @moondb.Value) -> String? {
  match v {
    Null => None
    Text(s) => Some(s)
    Blob(b) => Some(@utf8.decode_lossy(b[:]))
    Int64(n) => Some(n.to_string())
    Int(n) => Some(n.to_string())
    Double(d) => Some(d.to_string())
    Bool(b) => Some(if b { "1" } else { "0" })
  }
}

///|
pub fn row_text(r : @moondb.Row, col : String, default : String) -> String {
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
pub fn row_i64(r : @moondb.Row, col : String) -> Int64 {
  match r.by_name(col) {
    Some(v) =>
      match v {
        Int64(n) => n
        Int(n) => n.to_int64()
        Double(d) => d.to_int64()
        Text(s) =>
          try {
            @string.parse_int64(s)
          } catch {
            _ => 0L
          }
        _ => 0L
      }
    None => 0L
  }
}

///|
fn row_opt_i64(r : @moondb.Row, col : String) -> Int64? {
  match r.by_name(col) {
    Some(Null) | None => None
    Some(v) =>
      Some(
        match v {
          Int64(n) => n
          Int(n) => n.to_int64()
          Double(d) => d.to_int64()
          Text(s) =>
            try {
              @string.parse_int64(s)
            } catch {
              _ => 0L
            }
          _ => 0L
        },
      )
  }
}

///|
fn row_opt_int(r : @moondb.Row, col : String) -> Int? {
  match row_opt_i64(r, col) {
    Some(n) => Some(n.to_int())
    None => None
  }
}

///|
pub fn row_int_d(r : @moondb.Row, col : String, default : Int) -> Int {
  match row_opt_i64(r, col) {
    Some(n) => n.to_int()
    None => default
  }
}

///|
/// DATETIME 文本归一："yyyy-MM-dd HH:mm:ss[.fff]" → 截 19 位
fn norm_datetime(s : String) -> String {
  if s.length() > 19 {
    s[0:19].to_owned()
  } else {
    s
  }
}

///|
fn row_opt_datetime(r : @moondb.Row, col : String) -> String? {
  match row_opt_text(r, col) {
    Some(s) => if s.is_empty() { None } else { Some(norm_datetime(s)) }
    None => None
  }
}

///|
/// SqlValue → moondb 绑定值（builder 的中性值在执行边界转换）
pub fn to_db_values(vs : Array[@core.SqlValue]) -> Array[@moondb.Value] {
  let out : Array[@moondb.Value] = []
  for v in vs {
    out.push(
      match v {
        S(s) => @moondb.Text(s)
        I(n) => @moondb.Int(n)
        L(n) => @moondb.Int64(n)
        D(d) => @moondb.Double(d)
        B(b) => @moondb.Bool(b)
        N => @moondb.Null
      },
    )
  }
  out
}
