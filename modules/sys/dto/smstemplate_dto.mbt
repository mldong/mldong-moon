// sys_sms_template 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct SmsTemplateSaveReq {
  mut id : Int64
  mut biz_type : Int
  mut template_code : String
  mut provider : String
  mut content : String
  mut signature : String?
  mut enabled : Int?
  mut remark : String?
}

///|
let smstemplate_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "bizType": @moon_zod.number().int(),
  "templateCode": @moon_zod.string().max(64, msg="templateCode 最多 64 位"),
  "provider": @moon_zod.string().max(32, msg="provider 最多 32 位"),
  "content": @moon_zod.string(),
  "signature": @moon_zod.string().max(64, msg="signature 最多 64 位").optional(),
  "enabled": @moon_zod.number().int().optional(),
  "remark": @moon_zod.string().max(255, msg="remark 最多 255 位").optional(),
})

///|
/// 从 Json 提取 Req
fn smstemplate_req_of(data : Json) -> SmsTemplateSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    biz_type: @core.get_int(data, "bizType").unwrap_or(0),
    template_code: @core.text_or(data, "templateCode", ""),
    provider: @core.text_or(data, "provider", ""),
    content: @core.text_or(data, "content", ""),
    signature: @core.get_text(data, "signature"),
    enabled: @core.get_int(data, "enabled"),
    remark: @core.get_text(data, "remark"),
  }
}

///|
pub fn smstemplate_parse_save(body : Json) -> SmsTemplateSaveReq raise @core.MldongError {
  match smstemplate_save_schema.parse(body) {
    Ok(data) => smstemplate_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())
  }
}

///|
pub fn smstemplate_parse_update(body : Json) -> SmsTemplateSaveReq raise @core.MldongError {
  let req = smstemplate_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("SmsTemplateID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct SmsTemplatePageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn smstemplate_parse_page(body : Json) -> SmsTemplatePageReq raise @core.MldongError {
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
pub fn smstemplate_json(d : @entity.SmsTemplate) -> Json {
  {
    "id": d.id.to_string(),
    "bizType": Json::number(d.biz_type.to_double()),
    "templateCode": Json::string(d.template_code),
    "provider": Json::string(d.provider),
    "content": Json::string(d.content),
    "signature": jstr(d.signature),
    "enabled": jint(d.enabled),
    "remark": jstr(d.remark),
    "createUser": jsnow(d.create_user),
    "createTime": jstr(d.create_time),
    "updateUser": jsnow(d.update_user),
    "updateTime": jstr(d.update_time),
    "isDeleted": jint(d.is_deleted),
  }
}
