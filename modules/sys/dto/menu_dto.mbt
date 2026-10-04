// sys_menu 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct MenuSaveReq {
  mut id : Int64
  mut app_code : String?
  mut parent_id : Int64?
  mut name : String
  mut code : String
  mut menu_type : Int?
  mut sort : Int64?
  mut path : String?
  mut component : String?
  mut icon : String?
  mut is_show : Int?
  mut is_link : Int?
  mut url : String?
  mut enabled : Int?
  mut open_type : Int?
  mut is_cache : Int?
  mut is_sync : Int?
  mut variable : String?
}

///|
let menu_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "appCode": @moon_zod.string().max(32, msg="appCode 最多 32 位").optional(),
  "parentId": @moon_zod.any().optional(),
  "name": @moon_zod.string().max(64, msg="name 最多 64 位"),
  "code": @moon_zod.string().max(64, msg="code 最多 64 位"),
  "type": @moon_zod.number().int().optional(),
  "sort": @moon_zod.any().optional(),
  "path": @moon_zod.string().max(100, msg="path 最多 100 位").optional(),
  "component": @moon_zod.string().max(100, msg="component 最多 100 位").optional(),
  "icon": @moon_zod.string().max(100, msg="icon 最多 100 位").optional(),
  "isShow": @moon_zod.number().int().optional(),
  "isLink": @moon_zod.number().int().optional(),
  "url": @moon_zod.string().max(255, msg="url 最多 255 位").optional(),
  "enabled": @moon_zod.number().int().optional(),
  "openType": @moon_zod.number().int().optional(),
  "isCache": @moon_zod.number().int().optional(),
  "isSync": @moon_zod.number().int().optional(),
  "ext": @moon_zod.any().optional(),
})

///|
/// 从 Json 提取 Req
fn menu_req_of(data : Json) -> MenuSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    app_code: @core.get_text(data, "appCode"),
    parent_id: @core.get_i64(data, "parentId"),
    name: @core.text_or(data, "name", ""),
    code: @core.text_or(data, "code", ""),
    menu_type: @core.get_int(data, "type"),
    sort: @core.get_i64(data, "sort"),
    path: @core.get_text(data, "path"),
    component: @core.get_text(data, "component"),
    icon: @core.get_text(data, "icon"),
    is_show: @core.get_int(data, "isShow"),
    is_link: @core.get_int(data, "isLink"),
    url: @core.get_text(data, "url"),
    enabled: @core.get_int(data, "enabled"),
    open_type: @core.get_int(data, "openType"),
    is_cache: @core.get_int(data, "isCache"),
    is_sync: @core.get_int(data, "isSync"),
    variable: Some(match @core.get_ext_string(data, "ext") {
      Some(s) => s
      None => "{}"
    }),
  }
}

///|
pub fn menu_parse_save(body : Json) -> MenuSaveReq raise @core.MldongError {
  match menu_save_schema.parse(body) {
    Ok(data) => menu_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())
  }
}

///|
pub fn menu_parse_update(body : Json) -> MenuSaveReq raise @core.MldongError {
  let req = menu_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("MenuID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct MenuPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn menu_parse_page(body : Json) -> MenuPageReq raise @core.MldongError {
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
pub fn menu_json(d : @entity.Menu) -> Json {
  let obj : Json = {
    "id": d.id.to_string(),
    "appCode": jstr(d.app_code),
    "parentId": jsnow(d.parent_id),
    "name": Json::string(d.name),
    "code": Json::string(d.code),
    "pids": jstr(d.pids),
    "type": jint(d.menu_type),
    "sort": jsnow(d.sort),
    "path": jstr(d.path),
    "component": jstr(d.component),
    "icon": jstr(d.icon),
    "isShow": jint(d.is_show),
    "isLink": jint(d.is_link),
    "url": jstr(d.url),
    "enabled": jint(d.enabled),
    "openType": jint(d.open_type),
    "isCache": jint(d.is_cache),
    "isSync": jint(d.is_sync),
    "createTime": jstr(d.create_time),
    "createUser": jsnow(d.create_user),
    "updateTime": jstr(d.update_time),
    "updateUser": jsnow(d.update_user),
    "isDeleted": jint(d.is_deleted),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("menu_json 恒为 Object")
  }
  // ext 空不出键（UC-0426：'{}' 恒重写与 NULL 两态同判）
  match @core.ext_json_opt(d.variable) {
    Some(e) => { let _ = base.set("ext", e) }
    None => ()
  }
  Json::object(base)
}
