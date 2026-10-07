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
    Err(errors) => raise @core.MldongError::InvalidParam(errors[0].to_string())
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

///|
/// 路由菜单节点（boot2 RouteMenuVO / goframe RouteMenuVO 同形）：id/parentId 不出键，
/// name=菜单 code，meta 组装见 service；children 空不出键（boot2 NON_EMPTY 同语义）
pub(all) struct RouteNode {
  mut id : Int64
  mut parent_id : Int64
  mut name : String
  mut path : String?
  mut redirect : String?
  mut component : String?
  mut meta : Map[String, Json]
  mut children : Array[RouteNode]
}

///|
pub fn RouteNode::make(id : Int64, parent_id : Int64, m : @entity.Menu) -> RouteNode {
  {
    id,
    parent_id,
    name: m.code,
    path: m.path,
    redirect: None,
    component: m.component,
    meta: Map([], capacity=0),
    children: [],
  }
}

///|
pub fn route_node_json(n : RouteNode) -> Json {
  let obj : Json = {
    "name": Json::string(n.name),
    "path": jstr(n.path),
    "redirect": Json::string(n.redirect.unwrap_or("")),
    "component": jstr(n.component),
    "meta": Json::object(n.meta),
    "children": Json::array(n.children.map(route_node_json)),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("route_node_json 恒为 Object")
  }
  // redirect 空出键（boot2 redirect=null 序列化差异取 goframe 口径；children 空出键）
  match n.redirect {
    Some(r) => if r.is_empty() {
      let _ = base.remove("redirect")
    }
    None => {
      let _ = base.remove("redirect")
    }
  }
  if n.children.is_empty() {
    let _ = base.remove("children")
  }
  Json::object(base)
}

///|
/// 路由同步入参（boot2 SyncRouteParam 同形；嵌套 children 递归 upsert）
pub(all) struct SyncRouteReq {
  mut is_sync : Int?
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
  /// ext 序列化串（前端 ext 对象 → variable JSON 串；不带 = "{}"，boot2 同）
  mut variable : String?
  mut children : Array[SyncRouteReq]
}

///|
fn sync_route_of(data : Json) -> SyncRouteReq raise @core.MldongError {
  let children : Array[SyncRouteReq] = []
  match data {
    Object(map) =>
      match map.get("children") {
        Some(Json::Array(arr)) =>
          for c in arr {
            children.push(sync_route_of(c))
          }
        _ => ()
      }
    _ => ()
  }
  {
    is_sync: @core.get_int(data, "isSync"),
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
    variable: Some(match @core.get_ext_string(data, "ext") {
      Some(s) => s
      None => "{}"
    }),
    children,
  }
}

///|
pub fn menu_parse_sync(body : Json) -> Array[SyncRouteReq] raise @core.MldongError {
  match body {
    Json::Array(arr) => {
      let out : Array[SyncRouteReq] = []
      for c in arr {
        out.push(sync_route_of(c))
      }
      out
    }
    _ => raise @core.MldongError::InvalidInput("body 必须是路由数组")
  }
}
