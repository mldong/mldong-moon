// MySQL 连接与行读取助手 —— 形状照抄 jeeflow-moon repository-mysql（先例：每操作连接即取即用，
// autocommit；凭据只走 MLDONG_DB_* env，默认值不含密码）

///|
pub(all) struct MysqlConfig {
  host : String
  port : Int
  user : String
  password : String
  database : String
}

///|
pub fn MysqlConfig::from_env() -> MysqlConfig {
  let port = match @env.get_env_var("MLDONG_DB_PORT") {
    Some(s) =>
      try {
        @string.parse_int(s)
      } catch {
        _ => 3306
      }
    None => 3306
  }
  {
    host: @env.get_env_var("MLDONG_DB_HOST").unwrap_or("127.0.0.1"),
    port,
    user: @env.get_env_var("MLDONG_DB_USER").unwrap_or("root"),
    password: @env.get_env_var("MLDONG_DB_PWD").unwrap_or(""),
    database: @env.get_env_var("MLDONG_DB_NAME").unwrap_or("mldong-moon"),
  }
}

///|
async fn MysqlConfig::open_conn(self : MysqlConfig) -> @client.MysqlConn raise @core.MldongError {
  try {
    @client.MysqlConn::connect(self.host, self.port, self.user, self.password, self.database)
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
/// 可选绑定值：Some(v)→值，None→NULL
pub fn opt_text(v : String?) -> @moondb.Value {
  match v {
    Some(s) => @moondb.Text(s)
    None => @moondb.Null
  }
}

///|
pub fn opt_i64(v : Int64?) -> @moondb.Value {
  match v {
    Some(n) => @moondb.Int64(n)
    None => @moondb.Null
  }
}

///|
pub fn opt_int(v : Int?) -> @moondb.Value {
  match v {
    Some(n) => @moondb.Int(n)
    None => @moondb.Null
  }
}
