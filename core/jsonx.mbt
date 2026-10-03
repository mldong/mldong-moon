// Json 取值助手 —— dto/出参装配共用（Json::value()/as_string() 已 deprecated，走 Object(map) 模式）

///|
pub fn get_text(data : Json, key : String) -> String? {
  match data {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => Some(s)
        Some(Number(n, ..)) => Some(n.to_string())
        _ => None
      }
    _ => None
  }
}

///|
pub fn get_int(data : Json, key : String) -> Int? {
  match data {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => Some(n.to_int())
        Some(String(s)) =>
          try {
            Some(@string.parse_int(s))
          } catch {
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
pub fn get_i64(data : Json, key : String) -> Int64? {
  match data {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => Some(n.to_int64())
        Some(String(s)) =>
          try {
            Some(@string.parse_int64(s))
          } catch {
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
pub fn text_or(data : Json, key : String, default : String) -> String {
  match get_text(data, key) {
    Some(s) => s
    None => default
  }
}

///|
/// 提取 Int64 数组（remove 的 ids、grantRole 的 roleIds 等批量入参；
/// 雪花 id 兼容字符串/数字两种形态，字符串为准防 JS 精度丢失）
pub fn get_i64_array(body : Json, key : String) -> Array[Int64] {
  let out : Array[Int64] = []
  match body {
    Object(map) =>
      match map.get(key) {
        Some(Array(arr)) =>
          for v in arr {
            match v {
              Number(n, ..) => out.push(n.to_int64())
              String(s) =>
                try {
                  out.push(@string.parse_int64(s))
                } catch {
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  out
}

///|
/// 提取 ids 数组（remove 端点约定键）
pub fn get_ids(body : Json) -> Array[Int64] {
  get_i64_array(body, "ids")
}
