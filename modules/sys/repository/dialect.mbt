// 数据库连接缝 —— 方言解耦层：q/x/行读取器/事务助手全部中性（moondb.Row/Value +
// Conn trait），MySQL 知情面收口到本文件的 Box + 工厂；新方言 = 新 Box + 新分支。
// （moondb 另有同步 Driver trait + Pool[D:Driver] 接口缝，需要连接池时再评估切换；
//  本仓用自有异步 Conn 缝保持现有 async 语义零变化）

///|
/// 异步连接统一缝（方言 Box 各自实现；helper 与 BaseDao 只认本 trait）
pub(open) trait Conn {
  async fn query(Self, String, Array[@moondb.Value]) -> Array[@moondb.Row] raise @core.MldongError
  async fn execute(Self, String, Array[@moondb.Value]) -> @moondb.ExecResult raise @core.MldongError
  async fn begin(Self) -> Unit raise @core.MldongError
  async fn commit(Self) -> Unit raise @core.MldongError
  async fn rollback(Self) -> Unit raise @core.MldongError
  fn close(Self) -> Unit
}

///|
/// MySQL 方言包装（知情点：@client.MysqlConn）
pub(all) struct MysqlBox {
  conn : @client.MysqlConn
}

///|
pub impl Conn for MysqlBox with fn query(self, sql, params) {
  try {
    self.conn.query(sql, params)
  } catch {
    e => raise @core.MldongError::Internal("mysql query: \{e}")
  }
}

///|
pub impl Conn for MysqlBox with fn execute(self, sql, params) {
  try {
    self.conn.execute(sql, params)
  } catch {
    e => raise @core.MldongError::Internal("mysql execute: \{e}")
  }
}

///|
pub impl Conn for MysqlBox with fn begin(self) {
  try {
    self.conn.begin()
  } catch {
    e => raise @core.MldongError::Internal("mysql begin: \{e}")
  }
}

///|
pub impl Conn for MysqlBox with fn commit(self) {
  try {
    self.conn.commit()
  } catch {
    e => raise @core.MldongError::Internal("mysql commit: \{e}")
  }
}

///|
pub impl Conn for MysqlBox with fn rollback(self) {
  try {
    self.conn.rollback()
  } catch {
    e => raise @core.MldongError::Internal("mysql rollback: \{e}")
  }
}

///|
pub impl Conn for MysqlBox with fn close(self) {
  self.conn.close()
}

///|
/// 连接工厂（按 config.driver 分发；新方言 = 新 Box + 新分支）
pub async fn open_conn(config : @core.MysqlConfig) -> MysqlBox raise @core.MldongError {
  if config.driver != "mysql" {
    abort("方言未接入: \{config.driver}（当前仅 mysql；新方言按 dialect.mbt 的 Box 模式扩展）")
  }
  try {
    { conn: @client.MysqlConn::connect(config.host, config.port, config.user, config.password, config.database) }
  } catch {
    e => raise @core.MldongError::Internal("mysql connect: \{e}")
  }
}

///|
/// 查询归一助手（中性：任意 Conn）
pub async fn[T : Conn] q(
  conn : T,
  sql : String,
  params : Array[@moondb.Value],
) -> Array[@moondb.Row] raise @core.MldongError {
  conn.query(sql, params)
}

///|
/// 执行归一助手（中性：任意 Conn）
pub async fn[T : Conn] x(
  conn : T,
  sql : String,
  params : Array[@moondb.Value],
) -> @moondb.ExecResult raise @core.MldongError {
  conn.execute(sql, params)
}

///|
/// 归还连接（中性；每操作连接即取即用模式）
pub fn[T : Conn] close_conn(conn : T) -> Unit {
  conn.close()
}

///|
/// 事务开（配 tx_commit/tx_rollback 用；错误处理样板见 perm_repository.mbt grant_*）
pub async fn[T : Conn] tx_begin(conn : T) -> Unit raise @core.MldongError {
  conn.begin()
}

///|
pub async fn[T : Conn] tx_commit(conn : T) -> Unit raise @core.MldongError {
  conn.commit()
}

///|
pub async fn[T : Conn] tx_rollback(conn : T) -> Unit raise @core.MldongError {
  conn.rollback()
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

///|
pub extend MysqlBox with Conn::{
  query,
  execute,
  begin,
  commit,
  rollback,
  close,
}
