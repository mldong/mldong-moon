// sys_post 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct PostSaveReq {
  mut id : Int64
  mut name : String
  mut code : String
  mut sort : Int64?
  mut enabled : Int?
  mut remark : String?
  /// ext 扩展对象序列化串（存 variable 列）
  mut variable : String?
}

///|
let post_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "name": @moon_zod.string().max(64, msg="name 最多 64 位"),
  "code": @moon_zod.string().max(64, msg="code 最多 64 位"),
  "sort": @moon_zod.any().optional(),
  "enabled": @moon_zod.number().int().optional(),
  "remark": @moon_zod.string().max(255, msg="remark 最多 255 位").optional(),
})

///|
/// 从 Json 提取 Req
fn post_req_of(data : Json) -> PostSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    name: @core.text_or(data, "name", ""),
    code: @core.text_or(data, "code", ""),
    sort: @core.get_i64(data, "sort"),
    enabled: @core.get_int(data, "enabled"),
    remark: @core.get_text(data, "remark"),
    // boot2 同语义：Param.ext 默认空 Dict，不带 ext = "{}"（非 null）
    variable: Some(match @core.get_ext_string(data, "ext") {
      Some(s) => s
      None => "{}"
    }),
  }
}

///|
pub fn post_parse_save(body : Json) -> PostSaveReq raise @core.MldongError {
  match post_save_schema.parse(body) {
    Ok(data) => post_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidParam(errors[0].to_string())
  }
}

///|
pub fn post_parse_update(body : Json) -> PostSaveReq raise @core.MldongError {
  let req = post_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("PostID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct PostPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn post_parse_page(body : Json) -> PostPageReq raise @core.MldongError {
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
/// 出参装配：<Cls> → Json（camelCase；雪花 id 一律字符串化防 JS 精度丢失）；
/// ext 空不出键（boot2 NON_EMPTY / goframe omitempty 同语义，UC-0426 双读侧）
pub fn post_json(d : @entity.Post) -> Json {
  let obj : Json = {
    "id": d.id.to_string(),
    "name": Json::string(d.name),
    "code": Json::string(d.code),
    "sort": jsnow(d.sort),
    "enabled": jint(d.enabled),
    "remark": jstr(d.remark),
    "createTime": jstr(d.create_time),
    "createUser": jsnow(d.create_user),
    "updateTime": jstr(d.update_time),
    "updateUser": jsnow(d.update_user),
    "isDeleted": jint(d.is_deleted),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("post_json 恒为 Object")
  }
  match @core.ext_json_opt(d.variable) {
    Some(e) => {
      let _ = base.set("ext", e)
    }
    None => ()
  }
  Json::object(base)
}
