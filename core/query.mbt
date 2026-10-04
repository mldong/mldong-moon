// m_ 通用查询件 —— mldong 框架统一约定的 MoonBit 实现（对照 boot2 PageParam.buildQueryWrapper）：
//   键格式 m_{OP}_{camelCol}（3 段）/ m_{alias}_{OP}_{camelCol}（4 段带表别名）
//   操作符 EQ/NE/GT/GE/LT/LE/LIKE/NLIKE/LLIKE/RLIKE/BT/IN/NIN
//   列名 camelCase→snake_case；空值（null/空串/空数组）跳过；非法 OP 跳过
//   列名安全校验（形状白名单，防注入）
// 产出 core/sqlbuilder 的 Wrapper（零 ORM 条件组），由 service 叠加业务条件后交 dao

///|
/// camelCase → snake_case（同 boot2 toUnderlineCase）
pub fn to_underscore(camel : String) -> String {
  let b = StringBuilder()
  for ch in camel {
    let code = ch.to_int()
    if code >= 65 && code <= 90 {
      b.write_char('_')
      b.write_char((code + 32).unsafe_to_char())
    } else {
      b.write_char(ch)
    }
  }
  b.to_string()
}

///|
/// 列名安全校验：仅允许 `[alias.]col_name` 形状（字母开头，字母/数字/下划线/点），
/// 防止 m_ 列名夹带 SQL（白名单语义）
pub fn is_field_safe(col : String) -> Bool {
  if col.is_empty() {
    return false
  }
  let mut prev_dot = true // 开头按"点后"对待（要求字母）
  for ch in col {
    let code = ch.to_int()
    let is_lower = code >= 97 && code <= 122
    let is_upper = code >= 65 && code <= 90
    let is_digit = code >= 48 && code <= 57
    if ch == '.' {
      if prev_dot {
        return false
      }
      prev_dot = true
    } else if is_lower || is_upper {
      prev_dot = false
    } else if is_digit || ch == '_' {
      if prev_dot {
        return false // 点后必须字母
      }
    } else {
      return false
    }
  }
  !prev_dot
}

///|
/// Json 值 → 绑定值（Number 整数走 L——m_EQ_dictId 这类雪花 id 超 32 位，
/// I 会静默截断；带小数走 D；String→S；Bool→B；其余 None）
fn json_scalar(v : Json) -> SqlValue? {
  match v {
    Number(n, ..) => {
      let d = n
      if d == d.to_int64().to_double() {
        Some(L(d.to_int64()))
      } else {
        Some(D(d))
      }
    }
    String(s) => Some(S(s))
    True => Some(B(true))
    False => Some(B(false))
    _ => None
  }
}

///|
/// m_ 值判空：null / 空串 / 空数组跳过（mldong 框架 isEmpty 同款）
fn is_empty_value(v : Json) -> Bool {
  match v {
    Null => true
    String(s) => s.is_empty()
    Array(arr) => arr.is_empty()
    _ => false
  }
}

///|
/// 逗号串 → 数组（IN/NIN/BT 的字符串形态）
fn split_comma(s : String) -> Array[Json] {
  let out : Array[Json] = []
  for part in s.split(",") {
    out.push(Json::string(part.to_owned()))
  }
  out
}

///|
/// 解析 body 里全部 m_ 参数为动态条件组。
/// exclude：额外跳过的键（调用方传 pageNum/pageSize/keywords 等固定键）。
/// 未匹配任何操作符的键静默跳过（13 株 switch default 同款）。
pub fn parse_m_params(body : Json, exclude? : Array[String] = []) -> Wrapper {
  let w = where_()
  match body {
    Object(map) => {
      for k, v in map {
        if !k.has_prefix("m_") {
          continue
        }
        let mut excluded = false
        for e in exclude {
          if e == k {
            excluded = true
          }
        }
        if excluded || is_empty_value(v) {
          continue
        }
        let parts = split_segments(k)
        if parts.length() != 3 && parts.length() != 4 {
          continue
        }
        let (tbl, op, camel_col) = if parts.length() == 3 {
          ("", parts[1], parts[2])
        } else {
          (parts[1] + ".", parts[2], parts[3])
        }
        let col = tbl + to_underscore(camel_col)
        if !is_field_safe(col) {
          continue
        }
        apply_op(w, op, col, v)
      }
    }
    _ => ()
  }
  w
}

///|
/// 按 "_" 切段（m_ 后的段数决定 3/4 段式）
fn split_segments(k : String) -> Array[String] {
  // k 形如 m_EQ_userName / m_t_EQ_userName：去掉 "m_" 后按 "_" 切
  let rest = k[2:].to_owned()
  let out : Array[String] = ["m"]
  for seg in rest.split("_") {
    out.push(seg.to_owned())
  }
  out
}

///|
/// 操作符分派（13 个；未知跳过）
fn apply_op(w : Wrapper, op : String, col : String, v : Json) -> Unit {
  match op {
    "EQ" =>
      match json_scalar(v) {
        Some(x) => {
          let _ = w.eq(col, x)
        }
        None => ()
      }
    "NE" =>
      match json_scalar(v) {
        Some(x) => {
          let _ = w.ne(col, x)
        }
        None => ()
      }
    "GT" =>
      match json_scalar(v) {
        Some(x) => {
          let _ = w.gt(col, x)
        }
        None => ()
      }
    "GE" =>
      match json_scalar(v) {
        Some(x) => {
          let _ = w.ge(col, x)
        }
        None => ()
      }
    "LT" =>
      match json_scalar(v) {
        Some(x) => {
          let _ = w.lt(col, x)
        }
        None => ()
      }
    "LE" =>
      match json_scalar(v) {
        Some(x) => {
          let _ = w.le(col, x)
        }
        None => ()
      }
    "LIKE" =>
      match v {
        String(s) => {
          let _ = w.like(col, s)
        }
        _ => ()
      }
    "NLIKE" =>
      match v {
        String(s) => {
          let _ = w.not_like(col, s)
        }
        _ => ()
      }
    "LLIKE" =>
      match v {
        String(s) => {
          let _ = w.like_pat(col, "%\{s}")
        }
        _ => ()
      }
    "RLIKE" =>
      match v {
        String(s) => {
          let _ = w.like_pat(col, "\{s}%")
        }
        _ => ()
      }
    "IN" | "NIN" => {
      let items : Array[Json] = match v {
        Array(arr) => arr
        String(s) => if s.contains(",") {
          split_comma(s)
        } else {
          [v]
        }
        _ => [v]
      }
      let vals : Array[SqlValue] = []
      for it in items {
        match json_scalar(it) {
          Some(x) => vals.push(x)
          None => ()
        }
      }
      if !vals.is_empty() {
        if op == "IN" {
          let _ = w.in_(col, vals)
        } else {
          let _ = w.not_in(col, vals)
        }
      }
    }
    "BT" => {
      let items : Array[Json] = match v {
        Array(arr) => arr
        String(s) => if s.contains(",") {
          split_comma(s)
        } else {
          []
        }
        _ => []
      }
      if items.length() == 2 {
        match json_scalar(items[0]) {
          Some(lo) =>
            match json_scalar(items[1]) {
              Some(hi) => {
                let _ = w.ge(col, lo)
                let _ = w.le(col, hi)
              }
              None => ()
            }
          None => ()
        }
      }
    }
    _ => () // 未知操作符跳过
  }
}

///|
/// 解析 keywords + searchKeys（通用关键字搜索：多列 OR 模糊）。
/// 返回 (关键词串, 搜索列清单)；无 keywords 返回 ("", [])。
/// 列名同样过 is_field_safe 校验；用哪些列由调用方决定（前端可带表别名前缀）。
pub fn parse_keywords(
  body : Json,
  default_search_keys? : Array[String] = [],
) -> (String, Array[String]) {
  let (kw, raw_keys) = match body {
    Object(map) => {
      let kw = match map.get("keywords") {
        Some(String(s)) => s
        _ => ""
      }
      let raw = match map.get("searchKeys") {
        Some(String(s)) => s
        _ => ""
      }
      (kw, raw)
    }
    _ => ("", "")
  }
  parse_keywords_with_raw(kw, raw_keys, default_search_keys=default_search_keys)
}

///|
/// keywords/searchKeys 原文版（调用方已从 body 取出原文的场景）
pub fn parse_keywords_with_raw(
  keywords : String,
  search_keys : String,
  default_search_keys? : Array[String] = [],
) -> (String, Array[String]) {
  if keywords.is_empty() {
    return ("", [])
  }
  let keys : Array[String] = []
  if !search_keys.is_empty() {
    for seg in search_keys.split(",") {
      let col = seg.to_owned()
      if !col.is_empty() && is_field_safe(col) {
        keys.push(col)
      }
    }
  }
  if keys.is_empty() {
    for k in default_search_keys {
      keys.push(k)
    }
  }
  (keywords, keys)
}

///|
/// 解析 orderBy（goframe low_code 同约定）：逗号拆分，每段 `col [dir]`，
/// dir 含 desc/descend → 倒序，其余（含缺省）正序；列名 camel→snake（goframe CaseSnake 同款）
/// 后过 is_field_safe 白名单，不安全段（如 `sort;drop table t`）整段静默丢弃 → 回落表默认排序。
pub fn parse_order_by(body : Json) -> Array[(String, Bool)] {
  let raw = match body {
    Object(map) =>
      match map.get("orderBy") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  let out : Array[(String, Bool)] = []
  if raw.is_empty() {
    return out
  }
  for seg in raw.split(",") {
    let seg = seg.trim(chars=" \t").to_owned()
    if seg.is_empty() {
      continue
    }
    let parts : Array[String] = []
    for p in seg.split(" ") {
      let p = p.trim(chars=" \t").to_owned()
      if !p.is_empty() {
        parts.push(p)
      }
    }
    if parts.is_empty() {
      continue
    }
    let col = to_underscore(parts[0])
    let mut desc = false
    if parts.length() > 1 {
      let dir = parts[1].to_lower()
      desc = dir == "desc" || dir == "descend"
    }
    if !col.is_empty() && is_field_safe(col) {
      out.push((col, desc))
    }
  }
  out
}
