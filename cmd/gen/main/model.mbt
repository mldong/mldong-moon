// 列分类与命名 —— 生成器的形状决策层（模板渲染在 render.mbt）

///|
/// 归一化后的列视图
pub(all) struct Col {
  /// 列名（snake_case）
  name : String
  /// JSON 键（camelCase）
  json : String
  /// MoonBit 字段类型：Int64 / Int / String
  ftype : String
  /// 可空列 → Option
  option : Bool
  /// 主键
  is_pk : Bool
  /// varchar 长度（非 varchar 为 None）
  max_len : Int?
  /// 进 Req/写路（审计列/pids 只进实体读面；variable 以 ext 名义参与读写）
  business : Bool
  /// variable 扩展列：JSON 键名用 ext、schema any 占位、出参 parse 回对象
  is_ext : Bool
}

///|
/// 审计列：只进实体与 TableCodec 读面，不进 Req/写路（create_time 由模板给 now 缺省）
fn is_audit(name : String) -> Bool {
  name == "create_time" ||
  name == "update_time" ||
  name == "create_user" ||
  name == "update_user" ||
  name == "is_deleted"
}

///|
/// 实体专用列：boot2 语义下服务层不维护的列（pids 树表留档、variable 扩展 JSON）——
/// 只进实体读面，不进 Req/写路
fn is_entity_only(name : String) -> Bool {
  name == "pids"
}

///|
/// snake_case → camelCase
pub fn to_camel(s : String) -> String {
  let buf = StringBuilder()
  let mut upper_next = false
  for i in 0..<s.length() {
    match s.get_char(i) {
      Some(c) =>
        if c == '_' {
          upper_next = true
        } else if upper_next {
          buf.write_char((c.to_int() - 32).unsafe_to_char())
          upper_next = false
        } else {
          buf.write_char(c)
        }
      None => ()
    }
  }
  buf.to_string()
}

///|
/// 表名 → 类名（sys_dept → Dept：去模块前缀 + 驼峰）
pub fn table_to_class(table : String) -> String {
  let stripped = match table.find("_") {
    Some(i) => table[i + 1:].to_owned()
    None => table
  }
  let buf = StringBuilder()
  let mut upper_next = true
  for i in 0..<stripped.length() {
    match stripped.get_char(i) {
      Some(c) =>
        if c == '_' {
          upper_next = true
        } else if upper_next {
          buf.write_char((c.to_int() - 32).unsafe_to_char())
          upper_next = false
        } else {
          buf.write_char(c)
        }
      None => ()
    }
  }
  buf.to_string()
}

///|
/// varchar(N) → Some(N)
fn parse_max_len(column_type : String) -> Int? {
  // varchar(64) / char(2) 才有长度；int(11) 一类不取
  let has_len = column_type.has_prefix("varchar") || column_type.has_prefix("char")
  if !has_len {
    return None
  }
  let open = match column_type.find("(") {
    Some(i) => i
    None => return None
  }
  let close = match column_type.find(")") {
    Some(i) => i
    None => return None
  }
  if close <= open + 1 {
    return None
  }
  let digits = column_type[open + 1:close].to_owned()
  try {
    Some(@string.parse_int(digits))
  } catch {
    _ => None
  }
}

///|
/// ColumnMeta → Col（形状决策：类型映射 + 可空 + 业务面划定）
pub fn classify(c : @meta.ColumnMeta) -> Col {
  let business = !is_audit(c.name) && !is_entity_only(c.name)
  let required = c.is_nullable == "NO" && c.default_value is None && !is_audit(c.name)
  {
    name: c.name,
    json: if c.name == "variable" { "ext" } else { to_camel(c.name) },
    ftype: @meta.column_to_field_type(c),
    option: !required,
    is_pk: c.is_pk,
    max_len: parse_max_len(c.column_type),
    business,
    is_ext: c.name == "variable",
  }
}
