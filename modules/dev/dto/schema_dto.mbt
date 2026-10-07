// dev_schema 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct SchemaSaveReq {
  mut id : Int64
  mut schema_group_id : Int64?
  mut table_name : String
  mut remark : String
  mut other_remark : String?
  mut table_type : Int?
  mut form_type : Int?
  mut is_tree : Int?
  mut sort : Int64?
  mut icon : String?
  mut search_form_keys : String?
  mut list_keys : String?
  mut variable : String?
}

///|
let schema_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "schemaGroupId": @moon_zod.any().optional(),
  "tableName": @moon_zod.string().max(64, msg="tableName 最多 64 位"),
  "remark": @moon_zod.string().max(255, msg="remark 最多 255 位"),
  "otherRemark": @moon_zod.string().optional(),
  "tableType": @moon_zod.number().int().optional(),
  "formType": @moon_zod.number().int().optional(),
  "isTree": @moon_zod.number().int().optional(),
  "sort": @moon_zod.any().optional(),
  "icon": @moon_zod.string().max(100, msg="icon 最多 100 位").optional(),
  "searchFormKeys": @moon_zod.string().optional(),
  "listKeys": @moon_zod.string().optional(),
  "ext": @moon_zod.any().optional(),
})

///|
/// 从 Json 提取 Req
fn schema_req_of(data : Json) -> SchemaSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    schema_group_id: @core.get_i64(data, "schemaGroupId"),
    table_name: @core.text_or(data, "tableName", ""),
    remark: @core.text_or(data, "remark", ""),
    other_remark: @core.get_text(data, "otherRemark"),
    table_type: @core.get_int(data, "tableType"),
    form_type: @core.get_int(data, "formType"),
    is_tree: @core.get_int(data, "isTree"),
    sort: @core.get_i64(data, "sort"),
    icon: @core.get_text(data, "icon"),
    search_form_keys: @core.get_text(data, "searchFormKeys"),
    list_keys: @core.get_text(data, "listKeys"),
    variable: Some(match @core.get_ext_string(data, "ext") {
      Some(s) => s
      None => "{}"
    }),
  }
}

///|
pub fn schema_parse_save(body : Json) -> SchemaSaveReq raise @core.MldongError {
  match schema_save_schema.parse(body) {
    Ok(data) => schema_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidParam(errors[0].to_string())
  }
}

///|
pub fn schema_parse_update(body : Json) -> SchemaSaveReq raise @core.MldongError {
  let req = schema_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("SchemaID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct SchemaPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn schema_parse_page(body : Json) -> SchemaPageReq raise @core.MldongError {
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
pub fn schema_json(d : @entity.Schema) -> Json {
  let obj : Json = {
    "id": d.id.to_string(),
    "schemaGroupId": jsnow(d.schema_group_id),
    "tableName": Json::string(d.table_name),
    "remark": Json::string(d.remark),
    "otherRemark": jstr(d.other_remark),
    "tableType": jint(d.table_type),
    "formType": jint(d.form_type),
    "isTree": jint(d.is_tree),
    "sort": jsnow(d.sort),
    "icon": jstr(d.icon),
    "searchFormKeys": jstr(d.search_form_keys),
    "listKeys": jstr(d.list_keys),
    "variable": jstr(d.variable),
    "createTime": jstr(d.create_time),
    "createUser": jsnow(d.create_user),
    "updateTime": jstr(d.update_time),
    "updateUser": jsnow(d.update_user),
    "isDeleted": jint(d.is_deleted),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("schema_json 恒为 Object")
  }
  // dev 家族 ext 恒出键（空为 {}）：UC-0303 响应字段列了 ext、UC-0306 明写
  // 「无 ext 的模型返回 ext: {} 不是 null」——与 sys/dict 家族「空不出键」（UC-0426）是两面，
  // 别互相套用（boot2 SchemaVO 同样默认空 JSONObject）。
  let ext_val = match @core.ext_json_opt(d.variable) {
    Some(e) => e
    None => Json::object(Map([], capacity=0))
  }
  let _ = base.set("ext", ext_val)
  Json::object(base)
}

///|
/// updateDesigner 入参（boot2 SchemaParam(Groups.Update) + columns 列集合同形）：
/// 主表走 Save 契约，columns 原样透传 service（逐行宽松提取，schema_id/sort 由 service 钉）
pub(all) struct SchemaDesignerReq {
  mut save : SchemaSaveReq
  mut columns : Array[Json]
}

///|
pub fn schema_parse_designer(body : Json) -> SchemaDesignerReq raise @core.MldongError {
  let save = schema_parse_update(body)
  let cols : Array[Json] = []
  match body {
    Object(map) =>
      match map.get("columns") {
        Some(Array(items)) => {
          for c in items {
            cols.push(c)
          }
        }
        _ => ()
      }
    _ => ()
  }
  { save, columns: cols }
}

///|
/// 模型 VO（boot2 SchemaVO 同形）：实体全量 + 派生（moduleName/tableCamelName/className）
/// + columns（fieldCamelName/listSort/searchSort 派生）+ ext（空不出键）+ schemaGroup
pub fn schema_vo_json(
  d : @entity.Schema,
  columns : Array[@entity.SchemaField],
  group : Json,
) -> Json {
  let list_keys : Map[String, Int] = Map([], capacity=0)
  let mut i = 0
  for k in split_keys(d.list_keys) {
    if !(list_keys.get(k) is Some(_)) {
      let _ = list_keys.set(k, i)
    }
    i = i + 1
  }
  let search_keys : Map[String, Int] = Map([], capacity=0)
  let mut j = 0
  for k in split_keys(d.search_form_keys) {
    if !(search_keys.get(k) is Some(_)) {
      let _ = search_keys.set(k, j)
    }
    j = j + 1
  }
  let base = match schema_json(d) {
    Object(map) => map
    _ => abort("schema_json 恒为 Object")
  }
  let _ = base.set("moduleName", Json::string(module_name_of(d.table_name)))
  let _ = base.set("tableCamelName", Json::string(table_camel_name_of(d.table_name)))
  let _ = base.set("className", Json::string(class_name_of(d.table_name)))
  let arr : Array[Json] = []
  for c in columns {
    arr.push(schemafield_vo_json(c, list_keys.get(c.field_name), search_keys.get(c.field_name)))
  }
  let _ = base.set("columns", Json::array(arr))
  let _ = base.set("schemaGroup", group)
  Json::object(base)
}

///|
/// 分组 VO（boot2 SchemaGroupVO 同形：分组全字段 + ext 空不出键 + schemaList 基础 VO）
pub fn schema_group_vo_json(g : @entity.SchemaGroup, schemas : Array[@entity.Schema]) -> Json {
  let obj : Json = {
    "id": g.id.to_string(),
    "name": Json::string(g.name),
    "code": Json::string(g.code),
    "icon": jstr(g.icon),
    "sort": jsnow(g.sort),
    "remark": jstr(g.remark),
    "createTime": jstr(g.create_time),
    "createUser": jsnow(g.create_user),
    "updateTime": jstr(g.update_time),
    "updateUser": jsnow(g.update_user),
    "isDeleted": jint(g.is_deleted),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("schema_group_vo_json 恒为 Object")
  }
  let grp_ext = match @core.ext_json_opt(g.variable) {
    Some(e) => e
    None => Json::object(Map([], capacity=0))
  }
  let _ = base.set("ext", grp_ext)
  let arr : Array[Json] = []
  for d in schemas {
    arr.push(Json::object(schema_item_with_null_columns(d)))
  }
  let _ = base.set("schemaList", Json::array(arr))
  Json::object(base)
}

///|
/// 分组缺失时的伪造聚合（boot2 同位：id=schema.id+1、name=模型 remark、code=表驼峰名、schemaList=[自身]）
pub fn schema_group_stub_json(d : @entity.Schema) -> Json {
  let obj : Json = {
    "id": (d.id + 1L).to_string(),
    "name": Json::string(d.remark),
    "code": Json::string(table_camel_name_of(d.table_name)),
    "icon": jstr(d.icon),
    "sort": jsnow(d.sort),
    "remark": jstr(d.other_remark),
    "schemaList": Json::array([Json::object(schema_item_with_null_columns(d))]),
  }
  obj
}

///|
/// boot2 schemaList 项 = Schema 基础 VO（columns 未组装，null 占位）
fn schema_item_with_null_columns(d : @entity.Schema) -> Map[String, Json] {
  let item = match schema_json(d) {
    Object(map) => map
    _ => abort("schema_json 恒为 Object")
  }
  let _ = item.set("columns", Json::null())
  item
}

///|
/// 逗号分隔键拆分（去空白，空串 → 空数组）
fn split_keys(raw : String?) -> Array[String] {
  let out : Array[String] = []
  match raw {
    Some(s) =>
      if !s.is_empty() {
        for part in s.split(",") {
          let k = part.trim()
          if !k.is_empty() {
            out.push(k.to_owned())
          }
        }
      }
    None => ()
  }
  out
}
