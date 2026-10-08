// 通用动态表查询内核 —— goframe utility/low_code_util（Select/BuildQuery）+ boot2
// LowCodeServiceUtil 同位：/{module}/{table}/select 通用下拉、/lowCode/{table}/page|detail
// 动态表网关共用（controller 直用——纯基础设施无业务语义，SQL 收口在本包）。
// 防注入三件：表名字符白名单、**真列清单校验**（information_schema 一次拉取，
// searchKeys/labelKey/valueKey/orderBy 全过）、值全参数绑定（m_ 条件由 core is_field_safe
// 形状白名单先行）。

///|
pub(all) struct GenericDao {
  config : @core.MysqlConfig
}

///|
pub fn GenericDao::make(config : @core.MysqlConfig) -> GenericDao {
  { config, }
}

///|
/// select 入参（goframe base.PageParam 下拉协议同形）
pub(all) struct GenericSelectReq {
  mut page_num : Int
  mut page_size : Int
  mut keywords : String
  mut search_keys : String
  mut order_by : String
  mut label_key : String
  mut value_key : String
  mut ext_field_names : String
  mut include_type : Int
  mut include_ids : Array[Int64]
  mut m : @core.Wrapper
}

///|
/// lowCode 分页入参
pub(all) struct GenericPageReq {
  mut page_num : Int
  mut page_size : Int
  mut keywords : String
  mut search_keys : String
  mut order_by : String
  mut m : @core.Wrapper
}

///|
/// 表名字符白名单（goframe tableNameSafe 同款；snake 形状）
pub fn table_name_safe(table : String) -> Bool {
  if table.is_empty() {
    return false
  }
  let mut first = true
  for ch in table {
    let c = ch.to_int()
    let ok = if first {
      (c >= 97 && c <= 122) || c == 95
    } else {
      (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
    }
    if !ok {
      return false
    }
    first = false
  }
  true
}

///|
fn join_str(parts : Array[String], sep : String) -> String {
  let b = StringBuilder()
  for i, p in parts {
    if i > 0 {
      b.write_string(sep)
    }
    b.write_string(p)
  }
  b.to_string()
}

///|
/// 拉表真列清单（information_schema 一次查询；列名集合）
pub async fn GenericDao::table_columns(self : GenericDao, table : String) -> Map[String, String] raise @core.MldongError {
  if !table_name_safe(table) {
    raise @core.MldongError::InvalidInput("表名非法")
  }
  let conn = open_conn(self.config)
  let rows = q(
    conn,
    // 别名必写：MySQL 8.0 把 information_schema 的列标签返成大写（COLUMN_NAME），
    // 5.7 返小写；row_text 大小写敏感 ⇒ 不钉别名则在 8.0 上列清单恒空（lowCode 报"表无 id 列"、
    // m_ 过滤静默失效）。10-08 在一键栈（mysql:8.0.46）实测，本机 5.7 通道看不出问题。
    "SELECT column_name AS column_name, data_type AS data_type FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ?",
    [@moondb.Text(table)],
  )
  conn.close()
  let cols : Map[String, String] = Map([], capacity=0)
  for r in rows {
    let _ = cols.set(row_text(r, "column_name", ""), row_text(r, "data_type", ""))
  }
  cols
}

///|
/// 时间列判定（information_schema 的 data_type）：datetime/timestamp/date/time 四类
fn is_temporal_type(dtype : String) -> Bool {
  let t = dtype.to_lower()
  t.has_prefix("datetime") || t.has_prefix("timestamp") || t == "date" || t == "time"
}

///|
/// 行 → Json（family 口径：bigint 列雪花字符串化防精度；Int/Double 数值；Text 文本）
///
/// ⚠ 时间列不是 Text 回来的，是 **Blob(bytes)** 回来的（同包 `dialect.mbt` 里
/// `value_to_text` 那句"DATETIME 走文本截 19 位"就是这件事的另一半）——旧写法把 Blob 一律丢成
/// `Json::null()` ⇒ 低代码 `page|detail` 与引擎 `bizData` 两条出口的 create_time/update_time
/// 全是 null（库里有时值、前端显示空）。现在按 dtype 认出时间列，Blob/Text 两路都 utf8 解串，
/// 并截到 19 位与框架其它时间出口同形（`sys_user.createTime` 那一档）。
fn generic_row_to_json(r : @moondb.Row, cols : Map[String, String]) -> Json {
  let obj : Map[String, Json] = Map([], capacity=0)
  for name, dtype in cols {
    let v = match r.by_name(name) {
      Some(v) => v
      None => continue
    }
    let temporal = is_temporal_type(dtype)
    let j : Json = match v {
      Null => Json::null()
      // bigint 一律字符串化（雪花 id 防 JS 精度丢失；sort 等非雪花 bigint 家族同样出串）
      Int64(n) => Json::string(n.to_string())
      Int(n) => Json::number(n.to_double())
      Double(d) => Json::number(d)
      Bool(b) => Json::boolean(b)
      Text(s) => Json::string(if temporal { norm_datetime(s) } else { s })
      Blob(_) =>
        match value_to_text(v) {
          Some(s) => Json::string(if temporal { norm_datetime(s) } else { s })
          None => Json::null()
        }
    }
    // UC-0318/0319：动态表行出口一律 camelCase（后端负责转，前端不做 snake_case 兼容）
    let _ = obj.set(@core.to_camel_case(name), j)
  }
  Json::object(obj)
}

///|
/// WHERE 组装：is_deleted=0（列存在才加）+ keywords/searchKeys OR-LIKE（真列校验）+ m_ 叠加
fn generic_where(
  cols : Map[String, String],
  keywords : String,
  search_keys : String,
  w : @core.Wrapper,
) -> (String, Array[@core.SqlValue]) {
  let conds : Array[String] = []
  let params : Array[@core.SqlValue] = []
  if cols.get("is_deleted") is Some(_) {
    conds.push("is_deleted = 0")
  }
  // keywords + searchKeys：多列 OR LIKE（goframe 同款；列必须真存在）
  if !keywords.is_empty() && !search_keys.is_empty() {
    let likes : Array[String] = []
    for part in search_keys.split(",") {
      let col = part.trim().to_owned()
      if col.is_empty() || !(cols.get(col) is Some(_)) {
        continue
      }
      likes.push("\{col} LIKE ?")
      params.push(@core.S("%" + keywords + "%"))
    }
    if !likes.is_empty() {
      conds.push("(" + join_str(likes, " OR ") + ")")
    }
  }
  let (wsql_raw, wparams) = w.build()
  // Wrapper::build 返回带 "WHERE " 前缀的子句——此处conds按裸条件拼接，剥前缀
  let wsql = if wsql_raw.has_prefix("WHERE ") { wsql_raw["WHERE ".length():].to_owned() } else { wsql_raw }
  if !wsql.is_empty() {
    conds.push(wsql)
    for p in wparams {
      params.push(p)
    }
  }
  let where_sql = if conds.is_empty() { "" } else { " WHERE " + join_str(conds, " AND ") }
  (where_sql, params)
}

///|
/// 列名 camel → snake（extFieldNames 前端传 camel，SQL 列是 snake；ext 输出键保持 camel）
fn ext_column_of(name : String) -> String {
  @core.to_underscore(name)
}

///|
fn build_order_sql(orders : Array[(String, Bool)], cols : Map[String, String]) -> String {
  let parts : Array[String] = []
  for o in orders {
    let (col, desc) = o
    // 真列二次校验（parse_order_by_raw 只过形状白名单）
    if cols.get(col) is Some(_) {
      parts.push("\{col} \{if desc { "DESC" } else { "ASC" }}")
    }
  }
  if parts.is_empty() {
    ""
  } else {
    " ORDER BY " + join_str(parts, ", ")
  }
}

///|
fn label_value_of(
  r : @moondb.Row,
  label_col : String,
  value_col : String,
  ext_pairs : Array[(String, String)],
) -> Json {
  let label = match r.by_name(label_col) {
    Some(Text(s)) => s
    Some(Int64(n)) => n.to_string()
    Some(Int(n)) => n.to_string()
    _ => ""
  }
  let value = match r.by_name(value_col) {
    Some(Text(s)) => Json::string(s)
    Some(Int64(n)) => Json::string(n.to_string())
    Some(Int(n)) => Json::number(n.to_double())
    _ => Json::null()
  }
  let obj : Map[String, Json] = { "label": Json::string(label), "value": value }
  if !ext_pairs.is_empty() {
    let ext : Map[String, Json] = Map([], capacity=0)
    for pair in ext_pairs {
      let (camel, col) = pair
      match r.by_name(col) {
        Some(Text(s)) => { let _ = ext.set(camel, Json::string(s)) }
        Some(Int64(n)) => { let _ = ext.set(camel, Json::string(n.to_string())) }
        Some(Int(n)) => { let _ = ext.set(camel, Json::number(n.to_double())) }
        _ => ()
      }
    }
    let _ = obj.set("ext", Json::object(ext))
  }
  Json::object(obj)
}

///|
/// 通用下拉（goframe Select 同协议）：出参裸数组 [{label, value(str), ext?}]
pub async fn GenericDao::select(self : GenericDao, table : String, req : GenericSelectReq) -> Array[Json] raise @core.MldongError {
  let cols = self.table_columns(table)
  let label_col = ext_column_of(if req.label_key.is_empty() { "name" } else { req.label_key })
  let value_col = ext_column_of(if req.value_key.is_empty() { "id" } else { req.value_key })
  if !(cols.get(label_col) is Some(_)) || !(cols.get(value_col) is Some(_)) {
    raise @core.MldongError::InvalidInput("labelKey/valueKey 列不存在")
  }
  // ext 附加列（camel 传入 → snake 列；输出键 camel）
  let ext_pairs : Array[(String, String)] = []
  if !req.ext_field_names.is_empty() {
    for part in req.ext_field_names.split(",") {
      let camel = part.trim().to_owned()
      if camel.is_empty() {
        continue
      }
      let col = ext_column_of(camel)
      if cols.get(col) is Some(_) {
        ext_pairs.push((camel, col))
      }
    }
  }
  let (where_sql, params) = generic_where(cols, req.keywords, req.search_keys, req.m)
  let order_sql = build_order_sql(@core.parse_order_by_raw(req.order_by), cols)
  let conn = open_conn(self.config)
  errdefer close_conn(conn)
  let out : Array[Json] = []
  // includeType=2：仅查 includeIds（goframe 同款）
  if req.include_type == 2 && !req.include_ids.is_empty() {
    let marks = join_str(Array::makei(req.include_ids.length(), fn(_) { "?" }), ",")
    let sql = "SELECT * FROM \{table}\{where_sql} AND \{value_col} IN (\{marks})\{order_sql}"
    let ps = params.copy()
    for id in req.include_ids {
      ps.push(@core.L(id))
    }
    let rows = q(conn, sql, to_db_values(ps))
    for r in rows {
      out.push(label_value_of(r, label_col, value_col, ext_pairs))
    }
    return out
  }
  let page_size = if req.page_size <= 0 { 1000 } else { req.page_size }
  let page_num = if req.page_num <= 0 { 1 } else { req.page_num }
  let sql = "SELECT * FROM \{table}\{where_sql}\{order_sql} LIMIT \{page_size} OFFSET \{(page_num - 1) * page_size}"
  let rows = q(conn, sql, to_db_values(params))
  for r in rows {
    out.push(label_value_of(r, label_col, value_col, ext_pairs))
  }
  // includeType=1：includeIds 里不在当页结果的置顶补齐（回显已选项）
  if req.include_type == 1 && !req.include_ids.is_empty() {
    let seen : Map[String, Bool] = Map([], capacity=0)
    for item in out {
      match item {
        Object(m) =>
          match m.get("value") {
            Some(String(v)) => { let _ = seen.set(v, true) }
            _ => ()
          }
        _ => ()
      }
    }
    let missing : Array[Int64] = []
    for id in req.include_ids {
      if !(seen.get(id.to_string()) is Some(_)) {
        missing.push(id)
      }
    }
    if !missing.is_empty() {
      let marks = join_str(Array::makei(missing.length(), fn(_) { "?" }), ",")
      let sql2 = "SELECT * FROM \{table} WHERE \{value_col} IN (\{marks})"
      let ps2 : Array[@core.SqlValue] = []
      for id in missing {
        ps2.push(@core.L(id))
      }
      let rows2 = q(conn, sql2, to_db_values(ps2))
      let tops : Array[Json] = []
      for r in rows2 {
        tops.push(label_value_of(r, label_col, value_col, ext_pairs))
      }
      for t in tops {
        out.push(t)
      }
    }
  }
  out
}

///|
/// lowCode 分页（动态表五键分页；rows 全字段）
pub async fn GenericDao::page(self : GenericDao, table : String, req : GenericPageReq) -> (Int, Array[Json]) raise @core.MldongError {
  let cols = self.table_columns(table)
  let (where_sql, params) = generic_where(cols, req.keywords, req.search_keys, req.m)
  let order_sql = build_order_sql(@core.parse_order_by_raw(req.order_by), cols)
  let conn = open_conn(self.config)
  errdefer close_conn(conn)
  let count_rows = q(conn, "SELECT COUNT(*) AS c FROM \{table}\{where_sql}", to_db_values(params))
  let total = if count_rows.is_empty() { 0 } else { row_int_d(count_rows[0], "c", 0) }
  let page_size = if req.page_size <= 0 { 10 } else { req.page_size }
  let page_num = if req.page_num <= 0 { 1 } else { req.page_num }
  let sql = "SELECT * FROM \{table}\{where_sql}\{order_sql} LIMIT \{page_size} OFFSET \{(page_num - 1) * page_size}"
  let rows = q(conn, sql, to_db_values(params))
  let out : Array[Json] = []
  for r in rows {
    out.push(generic_row_to_json(r, cols))
  }
  (total, out)
}

///|
/// lowCode 详情（全字段单行）
pub async fn GenericDao::detail(self : GenericDao, table : String, id : Int64) -> Json? raise @core.MldongError {
  let cols = self.table_columns(table)
  if !(cols.get("id") is Some(_)) {
    raise @core.MldongError::InvalidInput("表无 id 列")
  }
  let where_sql = if cols.get("is_deleted") is Some(_) {
    " WHERE id = ? AND is_deleted = 0"
  } else {
    " WHERE id = ?"
  }
  let conn = open_conn(self.config)
  let rows = q(conn, "SELECT * FROM \{table}\{where_sql}", to_db_values([@core.L(id)]))
  conn.close()
  if rows.is_empty() {
    None
  } else {
    Some(generic_row_to_json(rows[0], cols))
  }
}

///|
/// 按**任意真列**等值取单行（jeeflow `bizData` 那一族的读侧：`WHERE process_instance_id = ?`）。
/// 列名进 SQL 前已过真列白名单（`table_columns` 拉的 information_schema 结果，表名本身先过
/// `table_name_safe`），值一律参数绑定 ⇒ 与 `detail` 同一条防注入链，不是新口子。
pub async fn GenericDao::row_by_column(
  self : GenericDao,
  table : String,
  column : String,
  value : Int64
) -> Json? raise @core.MldongError {
  let cols = self.table_columns(table)
  if !(cols.get(column) is Some(_)) {
    raise @core.MldongError::InvalidInput("列不存在: \{column}")
  }
  let where_sql = if cols.get("is_deleted") is Some(_) {
    " WHERE \{column} = ? AND is_deleted = 0"
  } else {
    " WHERE \{column} = ?"
  }
  let conn = open_conn(self.config)
  let rows = q(conn, "SELECT * FROM \{table}\{where_sql}", to_db_values([@core.L(value)]))
  conn.close()
  if rows.is_empty() {
    None
  } else {
    Some(generic_row_to_json(rows[0], cols))
  }
}
