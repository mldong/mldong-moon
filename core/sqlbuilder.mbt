// SQL 构建器 —— MyBatis-Plus QueryWrapper 式的条件组与单表语句构建
// 绑定值用中性 SqlValue（core 零 ORM 依赖），dao-mysql 侧转 @moondb.Value；
// 全部值走 ? 占位参数，永不拼进 SQL 文本（注入安全同 mldong 框架口径）

///|
/// 中性绑定值
pub(all) enum SqlValue {
  S(String)
  I(Int)
  L(Int64)
  D(Double)
  B(Bool)
  N
}

///|
/// 单个条件
pub(all) enum Cond {
  Eq(String, SqlValue)
  Ne(String, SqlValue)
  Like(String, String) // 自动包 %..%
  /// 完整 pattern 透传（LLIKE "%v"、RLIKE "v%"、NLIKE 反向等由调用方拼 pattern）
  LikePat(String, String)
  Gt(String, SqlValue)
  Ge(String, SqlValue)
  Lt(String, SqlValue)
  Le(String, SqlValue)
  In(String, Array[SqlValue])
  NotIn(String, Array[SqlValue])
  /// 原生片段 + 参数（OR 组合等复杂条件；片段里只写 ? 占位，值进参数）
  Raw(String, Array[SqlValue])
}

///|
/// 条件组（AND 语义；骨架不做 OR 组合，业务复杂条件在 dao 实现里手写 SQL）
pub(all) struct Wrapper {
  mut conds : Array[Cond]
}

///|
pub fn where_() -> Wrapper {
  { conds: [] }
}

///|
pub fn Wrapper::eq(self : Wrapper, col : String, v : SqlValue) -> Wrapper {
  self.conds.push(Eq(col, v))
  self
}

///|
pub fn Wrapper::ne(self : Wrapper, col : String, v : SqlValue) -> Wrapper {
  self.conds.push(Ne(col, v))
  self
}

///|
pub fn Wrapper::like(self : Wrapper, col : String, s : String) -> Wrapper {
  self.conds.push(Like(col, s))
  self
}

///|
/// NOT IN（空集合时条件不生效）
pub fn Wrapper::not_in(self : Wrapper, col : String, vs : Array[SqlValue]) -> Wrapper {
  self.conds.push(NotIn(col, vs))
  self
}

///|
/// 完整 pattern 的 LIKE（调用方自带通配符）
pub fn Wrapper::like_pat(self : Wrapper, col : String, pat : String) -> Wrapper {
  self.conds.push(LikePat(col, pat))
  self
}

///|
/// NOT LIKE %..%
pub fn Wrapper::not_like(self : Wrapper, col : String, s : String) -> Wrapper {
  self.conds.push(Raw("\{col} NOT LIKE ?", [S("%\{s}%")]))
  self
}

///|
pub fn Wrapper::gt(self : Wrapper, col : String, v : SqlValue) -> Wrapper {
  self.conds.push(Gt(col, v))
  self
}

///|
pub fn Wrapper::ge(self : Wrapper, col : String, v : SqlValue) -> Wrapper {
  self.conds.push(Ge(col, v))
  self
}

///|
pub fn Wrapper::lt(self : Wrapper, col : String, v : SqlValue) -> Wrapper {
  self.conds.push(Lt(col, v))
  self
}

///|
pub fn Wrapper::le(self : Wrapper, col : String, v : SqlValue) -> Wrapper {
  self.conds.push(Le(col, v))
  self
}

///|
/// 原生条件片段（如 keywords 双列 OR："(t.real_name like ? or t.user_name like ?)"）
pub fn Wrapper::raw(self : Wrapper, sql : String, params : Array[SqlValue]) -> Wrapper {
  self.conds.push(Raw(sql, params))
  self
}

///|
pub fn Wrapper::in_(self : Wrapper, col : String, vs : Array[SqlValue]) -> Wrapper {
  self.conds.push(In(col, vs))
  self
}

///|
/// 并入另一条件组（AND 语义追加；用于"业务硬条件 + m_ 动态条件"叠加）
pub fn Wrapper::append(self : Wrapper, other : Wrapper) -> Wrapper {
  for c in other.conds {
    self.conds.push(c)
  }
  self
}

///|
/// 条件组是否为空
pub fn Wrapper::is_empty(self : Wrapper) -> Bool {
  self.conds.is_empty()
}

///|
/// 构建 WHERE 子句（返回 ("", []) 当无条件；有条件时返回 ("WHERE c1 AND c2", 参数)）
pub fn Wrapper::build(self : Wrapper) -> (String, Array[SqlValue]) {
  if self.conds.is_empty() {
    return ("", [])
  }
  let parts : Array[String] = []
  let params : Array[SqlValue] = []
  for c in self.conds {
    match c {
      Eq(col, v) => {
        parts.push("\{col} = ?")
        params.push(v)
      }
      Ne(col, v) => {
        parts.push("\{col} <> ?")
        params.push(v)
      }
      Like(col, s) => {
        parts.push("\{col} LIKE ?")
        params.push(S("%\{s}%"))
      }
      LikePat(col, pat) => {
        parts.push("\{col} LIKE ?")
        params.push(S(pat))
      }
      Gt(col, v) => {
        parts.push("\{col} > ?")
        params.push(v)
      }
      Ge(col, v) => {
        parts.push("\{col} >= ?")
        params.push(v)
      }
      Lt(col, v) => {
        parts.push("\{col} < ?")
        params.push(v)
      }
      Le(col, v) => {
        parts.push("\{col} <= ?")
        params.push(v)
      }
      Raw(frag, rparams) => {
        parts.push(frag)
        for v in rparams {
          params.push(v)
        }
      }
      In(col, vs) => {
        if vs.is_empty() {
          // IN () 非法：空集合语义为"条件恒假"（对齐 mldong 框架约定"空不越权放行"）
          parts.push("1 = 0")
        } else {
          let marks = StringBuilder()
          for i, v in vs {
            if i > 0 {
              marks.write_string(",")
            }
            marks.write_string("?")
            params.push(v)
          }
          parts.push("\{col} IN (\{marks.to_string()})")
        }
      }
      NotIn(col, vs) => {
        // NOT IN () 恒真：空集合表示"不排除任何行"，条件整个跳过
        if !vs.is_empty() {
          let marks = StringBuilder()
          for i, v in vs {
            if i > 0 {
              marks.write_string(",")
            }
            marks.write_string("?")
            params.push(v)
          }
          parts.push("\{col} NOT IN (\{marks.to_string()})")
        }
      }
    }
  }
  ("WHERE \{parts.join(" AND ")}", params)
}

///|
/// SET 键值对（update 用；值为 N 的列在 build_update 时跳过 —— 对齐 MyBatis-Plus
/// updateById 的 null 字段不覆盖语义）
pub(all) struct SetPair {
  col : String
  val : SqlValue
}

///|
/// JOIN 子句：table 直接写"表 别名"（如 "sys_dept d"），on 手写（别名前缀透传）
pub(all) enum JoinKind {
  Left
  Inner
}

///|
pub(all) struct Join {
  kind : JoinKind
  /// "sys_dept d" 形式（别名一并写）
  table : String
  /// "t.dept_id = d.id"
  on : String
}

///|
/// SELECT 构建：cols 为空 = SELECT *（cols 支持别名表达式 "d.name as dept_name" 透传）；
/// orders = [(列, 是否倒序)] 多列排序；limit>0 生成分页
pub fn build_select(
  table : String,
  cols : Array[String],
  w : Wrapper,
  joins? : Array[Join] = [],
  orders? : Array[(String, Bool)] = [],
  limit? : Int = 0,
  offset? : Int = 0,
) -> (String, Array[SqlValue]) {
  let col_sql = if cols.is_empty() { "*" } else { cols.join(", ") }
  let (where_sql, params) = w.build()
  let mut sql = "SELECT \{col_sql} FROM \{table}"
  for j in joins {
    let kw = match j.kind {
      Left => "LEFT JOIN"
      Inner => "INNER JOIN"
    }
    sql = sql + " \{kw} \{j.table} ON \{j.on}"
  }
  sql = sql + " \{where_sql}"
  if !orders.is_empty() {
    let parts : Array[String] = []
    for o in orders {
      let (col, desc) = o
      parts.push("\{col} \{if desc { "DESC" } else { "ASC" }}")
    }
    sql = sql + " ORDER BY \{parts.join(", ")}"
  }
  if limit > 0 {
    sql = sql + " LIMIT ? OFFSET ?"
    params.push(I(limit))
    params.push(I(offset))
  }
  (sql, params)
}

///|
/// INSERT 构建
pub fn build_insert(table : String, pairs : Array[SetPair]) -> (String, Array[SqlValue]) {
  if pairs.is_empty() {
    abort("build_insert: empty pairs")
  }
  let cols = StringBuilder()
  let marks = StringBuilder()
  let params : Array[SqlValue] = []
  for i, p in pairs {
    if i > 0 {
      cols.write_string(",")
      marks.write_string(",")
    }
    cols.write_string(p.col)
    marks.write_string("?")
    params.push(p.val)
  }
  ("INSERT INTO \{table} (\{cols.to_string()}) VALUES (\{marks.to_string()})", params)
}

///|
/// UPDATE 构建：值为 N 的列跳过（null 不覆盖）；无条件时报错防全表更新
pub fn build_update(table : String, pairs : Array[SetPair], w : Wrapper) -> (String, Array[SqlValue]) {
  if w.is_empty() {
    abort("build_update: empty where would update the whole table")
  }
  let sets = StringBuilder()
  let params : Array[SqlValue] = []
  let mut first = true
  let mut any_set = false
  for p in pairs {
    match p.val {
      N => () // null 字段不覆盖
      v => {
        if first {
          first = false
        } else {
          sets.write_string(",")
        }
        sets.write_string("\{p.col}=?")
        params.push(v)
        any_set = true
      }
    }
  }
  if !any_set {
    abort("build_update: nothing to set")
  }
  let (where_sql, wparams) = w.build()
  for v in wparams {
    params.push(v)
  }
  ("UPDATE \{table} SET \{sets.to_string()} \{where_sql}", params)
}

///|
/// DELETE 构建（物理删；逻辑删走 build_update）
pub fn build_delete(table : String, w : Wrapper) -> (String, Array[SqlValue]) {
  if w.is_empty() {
    abort("build_delete: empty where would delete the whole table")
  }
  let (where_sql, params) = w.build()
  ("DELETE FROM \{table} \{where_sql}", params)
}
