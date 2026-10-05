// sys_vis_log 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct VisLogSaveReq {
  mut id : Int64
  mut name : String?
  mut success : String?
  mut message : String?
  mut ip : String?
  mut location : String?
  mut browser : String?
  mut os : String?
  mut vis_type : Int
  mut vis_time : String?
  mut account : String?
  mut sign_value : String?
}

///|
let vislog_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "name": @moon_zod.string().max(50, msg="name 最多 50 位").optional(),
  "success": @moon_zod.string().max(1, msg="success 最多 1 位").optional(),
  "message": @moon_zod.string().optional(),
  "ip": @moon_zod.string().max(255, msg="ip 最多 255 位").optional(),
  "location": @moon_zod.string().max(255, msg="location 最多 255 位").optional(),
  "browser": @moon_zod.string().max(255, msg="browser 最多 255 位").optional(),
  "os": @moon_zod.string().max(255, msg="os 最多 255 位").optional(),
  "visType": @moon_zod.number().int(),
  "visTime": @moon_zod.string().optional(),
  "account": @moon_zod.string().max(50, msg="account 最多 50 位").optional(),
  "signValue": @moon_zod.string().max(500, msg="signValue 最多 500 位").optional(),
})

///|
/// 从 Json 提取 Req
fn vislog_req_of(data : Json) -> VisLogSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    name: @core.get_text(data, "name"),
    success: @core.get_text(data, "success"),
    message: @core.get_text(data, "message"),
    ip: @core.get_text(data, "ip"),
    location: @core.get_text(data, "location"),
    browser: @core.get_text(data, "browser"),
    os: @core.get_text(data, "os"),
    vis_type: @core.get_int(data, "visType").unwrap_or(0),
    vis_time: @core.get_text(data, "visTime"),
    account: @core.get_text(data, "account"),
    sign_value: @core.get_text(data, "signValue"),
  }
}

///|
pub fn vislog_parse_save(body : Json) -> VisLogSaveReq raise @core.MldongError {
  match vislog_save_schema.parse(body) {
    Ok(data) => vislog_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())
  }
}

///|
pub fn vislog_parse_update(body : Json) -> VisLogSaveReq raise @core.MldongError {
  let req = vislog_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("VisLogID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct VisLogPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn vislog_parse_page(body : Json) -> VisLogPageReq raise @core.MldongError {
  let page_num = @core.get_int(body, "pageNum").unwrap_or(1)
  let page_size = @core.get_int(body, "pageSize").unwrap_or(10)
  if page_num <= 0 || page_size <= 0 || page_size > 200 {
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
pub fn vislog_json(d : @entity.VisLog) -> Json {
  {
    "id": d.id.to_string(),
    "name": jstr(d.name),
    "success": jstr(d.success),
    "message": jstr(d.message),
    "ip": jstr(d.ip),
    "location": jstr(d.location),
    "browser": jstr(d.browser),
    "os": jstr(d.os),
    "visType": Json::number(d.vis_type.to_double()),
    "visTime": jstr(d.vis_time),
    "account": jstr(d.account),
    "signValue": jstr(d.sign_value),
  }
}
