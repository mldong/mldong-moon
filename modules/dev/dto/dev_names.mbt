// dev 命名派生纯函数（boot2 SchemaVO/SchemaFieldVO 的派生属性同位）——
// 落 dto 层供 VO 装配与 service（importTable 分组前缀匹配）共用，纯字符串零 IO

///|
/// 下划线转小驼峰（SchemaFieldVO.fieldCamelName / tableCamelName 同一算法）：
/// user_name → userName；后续段首字母大写
pub fn camel_case(name : String) -> String {
  let b = StringBuilder()
  let mut up = false
  for ch in name {
    let code = ch.to_int()
    if code == 95 {
      // '_'
      up = true
    } else if up {
      if code >= 97 && code <= 122 {
        b.write_char((code - 32).unsafe_to_char())
      } else {
        b.write_char(ch)
      }
      up = false
    } else {
      b.write_char(ch)
    }
  }
  b.to_string()
}

///|
/// 模块名（SchemaVO.moduleName：表名首个 `_` 前段；无下划线空串）
pub fn module_name_of(table_name : String) -> String {
  if !table_name.contains("_") {
    // boot2：无下划线模块名空串（tableCamelName 退化为全名 camel）
    return ""
  }
  let b = StringBuilder()
  for ch in table_name {
    if ch.to_int() == 95 {
      break
    }
    b.write_char(ch)
  }
  b.to_string()
}

///|
/// 表小驼峰名（SchemaVO.tableCamelName：去 {模块名}_ 前缀后 camel）
pub fn table_camel_name_of(table_name : String) -> String {
  let mod_name = module_name_of(table_name)
  let prefix = "\{mod_name}_"
  let rest = if !mod_name.is_empty() && table_name.has_prefix(prefix) {
    table_name[mod_name.length() + 1:].to_owned()
  } else {
    table_name
  }
  camel_case(rest)
}

///|
/// 类名（SchemaVO.className：tableCamelName 首字母大写）
pub fn class_name_of(table_name : String) -> String {
  let camel = table_camel_name_of(table_name)
  if camel.is_empty() {
    return camel
  }
  let mut first = ""
  let mut rest = ""
  for i, ch in camel {
    let code = ch.to_int()
    if i == 0 {
      first = if code >= 97 && code <= 122 {
        (code - 32).unsafe_to_char().to_string()
      } else {
        ch.to_string()
      }
    } else {
      rest = camel[1:].to_owned()
      break
    }
  }
  first + rest
}
