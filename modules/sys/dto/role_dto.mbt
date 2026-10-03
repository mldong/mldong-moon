// sys_role 入参契约 —— schema + parse + Req + 出参装配（moon_zod 收口本层）

///|
pub(all) struct RoleSaveReq {
  mut id : Int64
  app_code : String?
  name : String
  code : String
  sort : Int64?
  role_type : Int?
  enabled : Int
  data_scope : Int?
  remark : String?
}

///|
let role_save_schema : @moon_zod.Schema = @moon_zod.object({
  // id 不参与校验但要在 strip 模式下存活（update 需要）
  "id": @moon_zod.any().optional(),
  "appCode": @moon_zod.string().max(32, msg="应用编码最多 32 位").optional(),
  "name": @moon_zod.string().min(1, msg="角色名称不能为空").max(64),
  "code": @moon_zod.string().max(64, msg="角色编码最多 64 位").optional(),
  "sort": @moon_zod.number().int().optional(),
  "roleType": @moon_zod.number().int().optional(),
  "enabled": @moon_zod.number().int(),
  "dataScope": @moon_zod.number().int().optional(),
  "remark": @moon_zod.string().max(255, msg="备注最多 255 位").optional(),
})

///|
fn role_req_of(data : Json) -> RoleSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    app_code: @core.get_text(data, "appCode"),
    name: @core.text_or(data, "name", ""),
    code: @core.text_or(data, "code", ""),
    sort: @core.get_i64(data, "sort"),
    role_type: @core.get_int(data, "roleType"),
    enabled: @core.get_int(data, "enabled").unwrap_or(1),
    data_scope: @core.get_int(data, "dataScope"),
    remark: @core.get_text(data, "remark"),
  }
}

///|
pub fn parse_role_save(body : Json) -> RoleSaveReq raise @core.MldongError {
  match role_save_schema.parse(body) {
    Ok(data) => role_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())
  }
}

///|
pub fn parse_role_update(body : Json) -> RoleSaveReq raise @core.MldongError {
  let req = parse_role_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("角色ID不能为空")
  }
  req
}

///|
/// 分页入参：m_ 动态条件（role 单表，3 段式）+ keywords/searchKeys
pub(all) struct RolePageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn parse_role_page(body : Json) -> RolePageReq raise @core.MldongError {
  let page_num = @core.get_int(body, "pageNum").unwrap_or(1)
  let page_size = @core.get_int(body, "pageSize").unwrap_or(10)
  if page_num <= 0 || page_size <= 0 || page_size > 200 {
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
/// 出参装配：Role → Json（camelCase，variable/create_user/update_user 骨架不回显）
pub fn role_json(r : @entity.Role) -> Json {
  {
    "id": r.id.to_string(),
    "appCode": jstr(r.app_code),
    "name": r.name,
    "code": r.code,
    "sort": jnum(r.sort),
    "roleType": jint(r.role_type),
    "enabled": r.enabled,
    "dataScope": jint(r.data_scope),
    "remark": jstr(r.remark),
    "createTime": jstr(r.create_time),
    "updateTime": jstr(r.update_time),
  }
}

///|
fn jnum(v : Int64?) -> Json {
  match v {
    Some(n) => Json::number(n.to_double())
    None => Json::null()
  }
}
