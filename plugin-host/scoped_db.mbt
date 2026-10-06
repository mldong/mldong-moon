// ScopedDb —— 命名空间绑定执行器（插件运行期唯一 DB 面）。
// 三重身份：
//   ① 归属闸：表名参数只接受"已声明的业务后缀"，p_<owner>_ 前缀由这里焊死——
//      作者没资格写全名，写错的机会不存在（前缀替换式方案仍给作者写全名的机会，这里连全名都不给）；
//   ② 串行闸：内部一把 @async.Mutex，query/execute 进出各一次——裸 Conn 被两个并发任务
//      交错使用 = 不可捕获的 wasm trap（真机两轮复现），这层是可用性防护不是风格；
//   ③ 事务主权隔离：不暴露 begin/commit/rollback——事务里第二个 BEGIN 会隐式提交前段，事务边界归装载器独占。
// 逃生通道 exec_raw：能用但不隐身——记越界嫌疑计数 + 日志点名；BEGIN/COMMIT/ROLLBACK
// 开头直接拒（SQL 是运行期构造的，装载期扫不到——运行期就是闸位）。

///|
pub struct ScopedDb {
  conn : @repo.MysqlBox
  owner : String
  prefix : String // "p_<owner>_"
  declared : Array[String] // descriptor.tables 业务后缀集（运行期唯一合法后缀）
  mutex : @async.Mutex
  mut raw_calls : Int // exec_raw 越界嫌疑计数（装载完成后落台账/启动日志点名）
}

///|
pub fn ScopedDb::make(
  conn : @repo.MysqlBox,
  owner : String,
  declared : Array[String],
) -> ScopedDb {
  {
    conn,
    owner,
    prefix: "p_\{owner}_",
    declared,
    mutex: @async.Mutex::Mutex(),
    raw_calls: 0,
  }
}

///|
/// 装载器取插件 DB 面的唯一入口（ScopedDb → &PluginDb trait object）
pub fn plugin_db_of(conn : @repo.MysqlBox, owner : String, declared : Array[String]) -> &@api.PluginDb {
  ScopedDb::make(conn, owner, declared)
}

///|
/// 越界嫌疑读数（装载完成后随启动日志点名 / 记台账 remark）
pub fn ScopedDb::raw_calls_count(self : ScopedDb) -> Int {
  self.raw_calls
}

///|
/// 归属闸：后缀必须 ∈ 声明集（传 "sys_user" 也被拒——错误含表名与所有者）。
/// 纯逻辑单抽（resolve_table），零 DB 可测；ScopedDb::check_table 只是绑 owner 的薄壳。
pub fn resolve_table(
  owner : String,
  declared : Array[String],
  suffix : String,
) -> String raise @core.MldongError {
  if declared.contains(suffix) {
    "p_\{owner}_\{suffix}"
  } else {
    let allowed = declared.join(",")
    raise @core.MldongError::Business(
      "运行期归属闸拒绝: 插件 \{owner} 试图访问 `p_\{owner}_\{suffix}`（未声明）——只许碰自己声明的表 [\{allowed}]",
    )
  }
}

///|
pub fn ScopedDb::check_table(self : ScopedDb, suffix : String) -> String raise @core.MldongError {
  resolve_table(self.owner, self.declared, suffix)
}

///|
/// 执行器内部：串行闸包一层的统一入口（defer 保证 raise 时也释放）
async fn[R] ScopedDb::with_lock(
  self : ScopedDb,
  op : async () -> R raise @core.MldongError,
) -> R raise @core.MldongError {
  self.mutex.acquire()
  defer self.mutex.release()
  op()
}

///|
impl @api.PluginDb for ScopedDb with fn select(
  self,
  table,
  cols,
  w,
) -> Array[@moondb.Row] raise @core.MldongError {
  let full = self.check_table(table)
  let (sql, params) = @core.build_select(full, cols, w)
  self.with_lock(async fn() raise @core.MldongError { @repo.q(self.conn, sql, @repo.to_db_values(params)) })
}

///|
impl @api.PluginDb for ScopedDb with fn insert(
  self,
  table,
  pairs,
) -> @moondb.ExecResult raise @core.MldongError {
  let full = self.check_table(table)
  let (sql, params) = @core.build_insert(full, pairs)
  self.with_lock(async fn() raise @core.MldongError { @repo.x(self.conn, sql, @repo.to_db_values(params)) })
}

///|
impl @api.PluginDb for ScopedDb with fn update(
  self,
  table,
  pairs,
  w,
) -> @moondb.ExecResult raise @core.MldongError {
  let full = self.check_table(table)
  let (sql, params) = @core.build_update(full, pairs, w)
  self.with_lock(async fn() raise @core.MldongError { @repo.x(self.conn, sql, @repo.to_db_values(params)) })
}

///|
impl @api.PluginDb for ScopedDb with fn delete(
  self,
  table,
  w,
) -> @moondb.ExecResult raise @core.MldongError {
  let full = self.check_table(table)
  let (sql, params) = @core.build_delete(full, w)
  self.with_lock(async fn() raise @core.MldongError { @repo.x(self.conn, sql, @repo.to_db_values(params)) })
}

///|
impl @api.PluginDb for ScopedDb with fn exec_raw(
  self,
  sql : String,
) -> @moondb.ExecResult raise @core.MldongError {
  // 运行期闸位：事务语句直接拒（装载期扫不到运行期构造的 SQL，这里就是闸位）
  let head = sql.trim().to_owned()
  let word = first_word(head)
  if is_transaction_word(word) {
    raise @core.MldongError::Business(
      "exec_raw 拒绝: 插件 \{self.owner} 试图执行事务语句 \{word}（事务主权归装载器独占——事务里第二个 BEGIN 会隐式提交前段）",
    )
  }
  self.raw_calls += 1
  let show = if head.length() < 80 {
    head
  } else {
    head[0:80].to_owned()
  }
  println(
    "[plugin-host] 越界嫌疑: 插件 \{self.owner} exec_raw（第 \{self.raw_calls} 次）— \{show}",
  )
  self.with_lock(async fn() raise @core.MldongError { @repo.x(self.conn, sql, []) })
}

///|
/// 事务语句首词（大小写不敏感；运行期闸位的判据）
pub fn is_transaction_word(word : String) -> Bool {
  let w = first_word(word)
  w == "begin" || w == "commit" || w == "rollback" || w == "start"
}

///|
/// 首个标识符 token（大小写不敏感比较用：逐字符小写化，不赌 to_upper/to_lower 的存在性）
fn first_word(s : String) -> String {
  let sb = StringBuilder()
  let n = s.length()
  for i in 0..<n {
    match s.get_char(i) {
      Some(c) => {
        let v = c.to_int()
        let letter = (v >= 0x61 && v <= 0x7A) ||
          (v >= 0x41 && v <= 0x5A) ||
          (v >= 0x30 && v <= 0x39) ||
          v == 0x5F
        if letter {
          if v >= 0x41 && v <= 0x5A {
            match (v + 0x20).to_char() {
              Some(lower) => sb.write_char(lower)
              None => sb.write_char(c)
            }
          } else {
            sb.write_char(c)
          }
        } else {
          break
        }
      }
      None => break
    }
  }
  sb.to_string()
}
