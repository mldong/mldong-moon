// sys_dict 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct DictSaveReq {
  mut id : Int64
  mut name : String
  mut code : String
  mut data_type : Int?
  mut group_code : String
  mut sort : Int64?
  mut enabled : Int?
  mut remark : String?
  mut variable : String?
}

///|
let dict_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "name": @moon_zod.string().max(64, msg="name 最多 64 位"),
  "code": @moon_zod.string().max(64, msg="code 最多 64 位"),
  "dataType": @moon_zod.number().int().optional(),
  "groupCode": @moon_zod.string().max(64, msg="groupCode 最多 64 位"),
  "sort": @moon_zod.any().optional(),
  "enabled": @moon_zod.number().int().optional(),
  "remark": @moon_zod.string().max(255, msg="remark 最多 255 位").optional(),
  "ext": @moon_zod.any().optional(),
})

///|
/// 从 Json 提取 Req
fn dict_req_of(data : Json) -> DictSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    name: @core.text_or(data, "name", ""),
    code: @core.text_or(data, "code", ""),
    data_type: @core.get_int(data, "dataType"),
    group_code: @core.text_or(data, "groupCode", ""),
    sort: @core.get_i64(data, "sort"),
    enabled: @core.get_int(data, "enabled"),
    remark: @core.get_text(data, "remark"),
    variable: Some(match @core.get_ext_string(data, "ext") {
      Some(s) => s
      None => "{}"
    }),
  }
}

///|
pub fn dict_parse_save(body : Json) -> DictSaveReq raise @core.MldongError {
  match dict_save_schema.parse(body) {
    Ok(data) => dict_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())
  }
}

///|
pub fn dict_parse_update(body : Json) -> DictSaveReq raise @core.MldongError {
  let req = dict_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("DictID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct DictPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn dict_parse_page(body : Json) -> DictPageReq raise @core.MldongError {
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
pub fn dict_json(d : @entity.Dict) -> Json {
  let obj : Json = {
    "id": d.id.to_string(),
    "name": Json::string(d.name),
    "code": Json::string(d.code),
    "dataType": jint(d.data_type),
    "groupCode": Json::string(d.group_code),
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
    _ => abort("dict_json 恒为 Object")
  }
  // ext 空不出键（UC-0426：'{}' 恒重写与 NULL 两态同判）
  match @core.ext_json_opt(d.variable) {
    Some(e) => { let _ = base.set("ext", e) }
    None => ()
  }
  Json::object(base)
}

///|
/// 清单出参：{name, dictKey, dataType?, items}——dataType None 不出键（空值兼作播种排除标记）。
/// 模型本体上收 core（DictModel/DictItemModel + EnumDictRegistry，框架件），此处只留渲染
pub fn dict_model_json(m : @core.DictModel) -> Json {
  let obj : Json = {
    "name": Json::string(m.name),
    "dictKey": Json::string(m.dict_key),
    "items": Json::array(m.items.map(dict_item_model_json)),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("dict_model_json 恒为 Object")
  }
  match m.data_type {
    Some(t) => {
      let _ = base.set("dataType", Json::number(t.to_double()))
    }
    None => ()
  }
  Json::object(base)
}

///|
fn dict_item_model_json(m : @core.DictItemModel) -> Json {
  let obj : Json = {
    "name": Json::string(m.name),
    "dictItemValue": m.dict_item_value,
    "dictItemKey": Json::string(m.dict_item_key),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("dict_item_model_json 恒为 Object")
  }
  match m.ext {
    Some(e) => {
      let _ = base.set("ext", e)
    }
    None => ()
  }
  Json::object(base)
}

///|
/// 清单数组出参
pub fn dict_model_list_json(models : Array[@core.DictModel]) -> Json {
  Json::array(models.map(dict_model_json))
}
