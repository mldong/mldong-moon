// sys_op_log 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct OpLogSaveReq {
  mut id : Int64
  mut name : String?
  mut op_type : Int?
  mut success : String?
  mut message : String?
  mut ip : String?
  mut location : String?
  mut browser : String?
  mut os : String?
  mut url : String?
  mut class_name : String?
  mut method_name : String?
  mut req_method : String?
  mut param : String?
  mut result : String?
  mut op_time : String?
  mut account : String?
  mut play_user_account : String?
  mut request_no : String?
  mut sign_value : String?
}

///|
let oplog_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "name": @moon_zod.string().max(50, msg="name 最多 50 位").optional(),
  "opType": @moon_zod.number().int().optional(),
  "success": @moon_zod.string().max(1, msg="success 最多 1 位").optional(),
  "message": @moon_zod.string().optional(),
  "ip": @moon_zod.string().max(255, msg="ip 最多 255 位").optional(),
  "location": @moon_zod.string().max(255, msg="location 最多 255 位").optional(),
  "browser": @moon_zod.string().max(255, msg="browser 最多 255 位").optional(),
  "os": @moon_zod.string().max(255, msg="os 最多 255 位").optional(),
  "url": @moon_zod.string().max(500, msg="url 最多 500 位").optional(),
  "className": @moon_zod.string().max(500, msg="className 最多 500 位").optional(),
  "methodName": @moon_zod.string().max(500, msg="methodName 最多 500 位").optional(),
  "reqMethod": @moon_zod.string().max(255, msg="reqMethod 最多 255 位").optional(),
  "param": @moon_zod.string().optional(),
  "result": @moon_zod.string().optional(),
  "opTime": @moon_zod.string().optional(),
  "account": @moon_zod.string().max(50, msg="account 最多 50 位").optional(),
  "playUserAccount": @moon_zod.string().max(50, msg="playUserAccount 最多 50 位").optional(),
  "requestNo": @moon_zod.string().max(64, msg="requestNo 最多 64 位").optional(),
  "signValue": @moon_zod.string().max(500, msg="signValue 最多 500 位").optional(),
})

///|
/// 从 Json 提取 Req
fn oplog_req_of(data : Json) -> OpLogSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    name: @core.get_text(data, "name"),
    op_type: @core.get_int(data, "opType"),
    success: @core.get_text(data, "success"),
    message: @core.get_text(data, "message"),
    ip: @core.get_text(data, "ip"),
    location: @core.get_text(data, "location"),
    browser: @core.get_text(data, "browser"),
    os: @core.get_text(data, "os"),
    url: @core.get_text(data, "url"),
    class_name: @core.get_text(data, "className"),
    method_name: @core.get_text(data, "methodName"),
    req_method: @core.get_text(data, "reqMethod"),
    param: @core.get_text(data, "param"),
    result: @core.get_text(data, "result"),
    op_time: @core.get_text(data, "opTime"),
    account: @core.get_text(data, "account"),
    play_user_account: @core.get_text(data, "playUserAccount"),
    request_no: @core.get_text(data, "requestNo"),
    sign_value: @core.get_text(data, "signValue"),
  }
}

///|
pub fn oplog_parse_save(body : Json) -> OpLogSaveReq raise @core.MldongError {
  match oplog_save_schema.parse(body) {
    Ok(data) => oplog_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidParam(errors[0].to_string())
  }
}

///|
pub fn oplog_parse_update(body : Json) -> OpLogSaveReq raise @core.MldongError {
  let req = oplog_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("OpLogID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct OpLogPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn oplog_parse_page(body : Json) -> OpLogPageReq raise @core.MldongError {
  let page_num = @core.get_int(body, "pageNum").unwrap_or(1)
  let page_size = @core.get_int(body, "pageSize").unwrap_or(10)
  if page_num <= 0 || page_size <= 0 {
    raise @core.MldongError::InvalidInput("分页参数非法")
  }
  {
    page_num,
    page_size,
    m: @core.parse_m_params(body, exclude=["pageNum", "pageSize", "keywords", "searchKeys", "orderBy"]),
    keywords: @core.text_or(body, "keywords", ""),
    search_keys: @core.text_or(body, "searchKeys", ""),
  }
}

///|
/// 出参装配：<Cls> → Json（camelCase；雪花 id 一律字符串化防 JS 精度丢失）
pub fn oplog_json(d : @entity.OpLog) -> Json {
  {
    "id": d.id.to_string(),
    "name": jstr(d.name),
    "opType": jint(d.op_type),
    "success": jstr(d.success),
    "message": jstr(d.message),
    "ip": jstr(d.ip),
    "location": jstr(d.location),
    "browser": jstr(d.browser),
    "os": jstr(d.os),
    "url": jstr(d.url),
    "className": jstr(d.class_name),
    "methodName": jstr(d.method_name),
    "reqMethod": jstr(d.req_method),
    "param": jstr(d.param),
    "result": jstr(d.result),
    "opTime": jstr(d.op_time),
    "account": jstr(d.account),
    "playUserAccount": jstr(d.play_user_account),
    "requestNo": jstr(d.request_no),
    "signValue": jstr(d.sign_value),
  }
}
