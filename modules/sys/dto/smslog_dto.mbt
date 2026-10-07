// sys_sms_log 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct SmsLogSaveReq {
  mut id : Int64
  mut task_id : Int64?
  mut phone : String
  mut biz_type : Int
  mut provider : String?
  mut content : String?
  mut status : Int?
  mut error_msg : String?
  mut cost_ms : Int?
  mut client_ip : String?
}

///|
let smslog_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "taskId": @moon_zod.any().optional(),
  "phone": @moon_zod.string().max(20, msg="phone 最多 20 位"),
  "bizType": @moon_zod.number().int(),
  "provider": @moon_zod.string().max(32, msg="provider 最多 32 位").optional(),
  "content": @moon_zod.string().optional(),
  "status": @moon_zod.number().int().optional(),
  "errorMsg": @moon_zod.string().max(500, msg="errorMsg 最多 500 位").optional(),
  "costMs": @moon_zod.number().int().optional(),
  "clientIp": @moon_zod.string().max(64, msg="clientIp 最多 64 位").optional(),
})

///|
/// 从 Json 提取 Req
fn smslog_req_of(data : Json) -> SmsLogSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    task_id: @core.get_i64(data, "taskId"),
    phone: @core.text_or(data, "phone", ""),
    biz_type: @core.get_int(data, "bizType").unwrap_or(0),
    provider: @core.get_text(data, "provider"),
    content: @core.get_text(data, "content"),
    status: @core.get_int(data, "status"),
    error_msg: @core.get_text(data, "errorMsg"),
    cost_ms: @core.get_int(data, "costMs"),
    client_ip: @core.get_text(data, "clientIp"),
  }
}

///|
pub fn smslog_parse_save(body : Json) -> SmsLogSaveReq raise @core.MldongError {
  match smslog_save_schema.parse(body) {
    Ok(data) => smslog_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidParam(errors[0].to_string())
  }
}

///|
pub fn smslog_parse_update(body : Json) -> SmsLogSaveReq raise @core.MldongError {
  let req = smslog_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("SmsLogID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct SmsLogPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn smslog_parse_page(body : Json) -> SmsLogPageReq raise @core.MldongError {
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
pub fn smslog_json(d : @entity.SmsLog) -> Json {
  {
    "id": d.id.to_string(),
    "taskId": jsnow(d.task_id),
    "phone": Json::string(d.phone),
    "bizType": Json::number(d.biz_type.to_double()),
    "provider": jstr(d.provider),
    "content": jstr(d.content),
    "status": jint(d.status),
    "errorMsg": jstr(d.error_msg),
    "costMs": jint(d.cost_ms),
    "clientIp": jstr(d.client_ip),
    "createTime": jstr(d.create_time),
    "updateTime": jstr(d.update_time),
  }
}
