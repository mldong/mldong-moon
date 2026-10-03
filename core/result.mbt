// 响应信封 —— 对齐 boot2 CommonResult：HTTP 恒 200 + {"code":0,"msg":"..","data":..}

///|
pub fn ok_empty() -> Json {
  { "code": 0, "msg": "ok", "data": Json::null() }
}

///|
pub fn ok_data(data : Json) -> Json {
  { "code": 0, "msg": "ok", "data": data }
}

///|
pub fn fail(code : Int, msg : String) -> Json {
  { "code": code, "msg": msg, "data": Json::null() }
}

///|
/// 错误 → 信封（cmd/main 全局转换的单点）
pub fn fail_of(err : MldongError) -> Json {
  fail(err.code(), err.message())
}

///|
/// CommonPage 形状分页信封（对齐 boot2 CommonPage：recordCount/totalPage/pageSize/pageNum/rows）
pub fn ok_page(page_num : Int, page_size : Int, total : Int, rows : Array[Json]) -> Json {
  let total_page = if page_size <= 0 {
    0
  } else {
    (total + page_size - 1) / page_size
  }
  let data : Json = {
    "recordCount": total,
    "totalPage": total_page,
    "pageSize": page_size,
    "pageNum": page_num,
    "rows": Json::array(rows),
  }
  ok_data(data)
}
