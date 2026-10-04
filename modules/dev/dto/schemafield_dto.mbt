// dev_schema_field 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct SchemaFieldSaveReq {
  mut id : Int64
  mut schema_id : Int64
  mut field_name : String
  mut remark : String
  mut field_size : Int?
  mut data_type : String?
  mut is_primary : Int?
  mut nullable : Int?
  mut default_value : String?
  mut component : String?
  mut sort : Int64?
  mut variable : String?
}

///|
let schemafield_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "schemaId": @moon_zod.any().optional(),
  "fieldName": @moon_zod.string().max(100, msg="fieldName 最多 100 位"),
  "remark": @moon_zod.string().max(255, msg="remark 最多 255 位"),
  "fieldSize": @moon_zod.number().int().optional(),
  "dataType": @moon_zod.string().max(100, msg="dataType 最多 100 位").optional(),
  "isPrimary": @moon_zod.number().int().optional(),
  "nullable": @moon_zod.number().int().optional(),
  "defaultValue": @moon_zod.string().optional(),
  "component": @moon_zod.string().max(100, msg="component 最多 100 位").optional(),
  "sort": @moon_zod.any().optional(),
  "ext": @moon_zod.any().optional(),
})

///|
/// 从 Json 提取 Req（pub：updateDesigner columns 逐行宽松提取复用）
pub fn schemafield_req_of(data : Json) -> SchemaFieldSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    schema_id: @core.get_i64(data, "schemaId").unwrap_or(0L),
    field_name: @core.text_or(data, "fieldName", ""),
    remark: @core.text_or(data, "remark", ""),
    field_size: @core.get_int(data, "fieldSize"),
    data_type: @core.get_text(data, "dataType"),
    is_primary: @core.get_int(data, "isPrimary"),
    nullable: @core.get_int(data, "nullable"),
    default_value: @core.get_text(data, "defaultValue"),
    component: @core.get_text(data, "component"),
    sort: @core.get_i64(data, "sort"),
    variable: Some(match @core.get_ext_string(data, "ext") {
      Some(s) => s
      None => "{}"
    }),
  }
}

///|
pub fn schemafield_parse_save(body : Json) -> SchemaFieldSaveReq raise @core.MldongError {
  match schemafield_save_schema.parse(body) {
    Ok(data) => schemafield_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())
  }
}

///|
pub fn schemafield_parse_update(body : Json) -> SchemaFieldSaveReq raise @core.MldongError {
  let req = schemafield_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("SchemaFieldID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct SchemaFieldPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn schemafield_parse_page(body : Json) -> SchemaFieldPageReq raise @core.MldongError {
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
pub fn schemafield_json(d : @entity.SchemaField) -> Json {
  let obj : Json = {
    "id": d.id.to_string(),
    "schemaId": d.schema_id.to_string(),
    "fieldName": Json::string(d.field_name),
    "remark": Json::string(d.remark),
    "fieldSize": jint(d.field_size),
    "dataType": jstr(d.data_type),
    "isPrimary": jint(d.is_primary),
    "nullable": jint(d.nullable),
    "defaultValue": jstr(d.default_value),
    "component": jstr(d.component),
    "sort": jsnow(d.sort),
    "createTime": jstr(d.create_time),
    "createUser": jsnow(d.create_user),
    "updateTime": jstr(d.update_time),
    "updateUser": jsnow(d.update_user),
    "isDeleted": jint(d.is_deleted),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("schemafield_json 恒为 Object")
  }
  // ext 空不出键（UC-0426：'{}' 恒重写与 NULL 两态同判）
  match @core.ext_json_opt(d.variable) {
    Some(e) => { let _ = base.set("ext", e) }
    None => ()
  }
  Json::object(base)
}

///|
/// 字段 VO（boot2 SchemaFieldVO 同形）：实体全量 + fieldCamelName + listSort/searchSort
/// （boot2 = listKeys/searchFormKeys 的 indexOf：0 基，不在集内 -1）+ ext（恒出键，空对象）
pub fn schemafield_vo_json(
  d : @entity.SchemaField,
  list_sort : Int?,
  search_sort : Int?,
) -> Json {
  let base = match schemafield_json(d) {
    Object(map) => map
    _ => abort("schemafield_json 恒为 Object")
  }
  let _ = base.set("fieldCamelName", Json::string(camel_case(d.field_name)))
  let _ = base.set("listSort", jint(list_sort))
  let _ = base.set("searchSort", jint(search_sort))
  // boot2 VO.ext 默认空 JSONObject 恒序列化——与 sys 域「空不出键」不同面，照 boot2
  let ext_val = match @core.ext_json_opt(d.variable) {
    Some(e) => e
    None => Json::object(Map([], capacity=0))
  }
  let _ = base.set("ext", ext_val)
  Json::object(base)
}
