// sys_config 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct ConfigSaveReq {
  mut id : Int64
  mut name : String
  mut code : String
  mut group_code : String
  mut content : String?
  mut is_sys : Int?
  mut enabled : Int?
  mut remark : String?
}

///|
let config_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "name": @moon_zod.string().max(64, msg="name 最多 64 位"),
  "code": @moon_zod.string().max(64, msg="code 最多 64 位"),
  "groupCode": @moon_zod.string().max(64, msg="groupCode 最多 64 位"),
  "content": @moon_zod.string().max(1000, msg="content 最多 1000 位").optional(),
  "isSys": @moon_zod.number().int().optional(),
  "enabled": @moon_zod.number().int().optional(),
  "remark": @moon_zod.string().max(255, msg="remark 最多 255 位").optional(),
})

///|
/// 从 Json 提取 Req
fn config_req_of(data : Json) -> ConfigSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    name: @core.text_or(data, "name", ""),
    code: @core.text_or(data, "code", ""),
    group_code: @core.text_or(data, "groupCode", ""),
    content: @core.get_text(data, "content"),
    is_sys: @core.get_int(data, "isSys"),
    enabled: @core.get_int(data, "enabled"),
    remark: @core.get_text(data, "remark"),
  }
}

///|
pub fn config_parse_save(body : Json) -> ConfigSaveReq raise @core.MldongError {
  match config_save_schema.parse(body) {
    Ok(data) => config_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidParam(errors[0].to_string())
  }
}

///|
pub fn config_parse_update(body : Json) -> ConfigSaveReq raise @core.MldongError {
  let req = config_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("ConfigID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct ConfigPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn config_parse_page(body : Json) -> ConfigPageReq raise @core.MldongError {
  let page_num = @core.get_int(body, "pageNum").unwrap_or(1)
  let page_size = @core.get_int(body, "pageSize").unwrap_or(10)
  if page_num <= 0 || page_size <= 0 {
    raise @core.MldongError::InvalidInput("分页参数非法")
  }
  {
    page_num,
    page_size,
    m: @core.parse_m_params(body, exclude=["pageNum", "pageSize", "keywords", "searchKeys"]),
    keywords: @core.text_or(body, "keywords", ""),
    search_keys: @core.text_or(body, "searchKeys", ""),
  }
}

///|
/// 出参装配：<Cls> → Json（camelCase；雪花 id 一律字符串化防 JS 精度丢失）
pub fn config_json(d : @entity.Config) -> Json {
  {
    "id": d.id.to_string(),
    "name": Json::string(d.name),
    "code": Json::string(d.code),
    "groupCode": Json::string(d.group_code),
    "content": jstr(d.content),
    "isSys": jint(d.is_sys),
    "enabled": jint(d.enabled),
    "remark": jstr(d.remark),
    "createTime": jstr(d.create_time),
    "createUser": jsnow(d.create_user),
    "updateTime": jstr(d.update_time),
    "updateUser": jsnow(d.update_user),
    "isDeleted": jint(d.is_deleted),
  }
}
