// sys_message 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct MessageSaveReq {
  mut id : Int64
  mut title : String
  mut content : String?
  mut msg_type : Int
  mut biz_type : String
  mut biz_id : Int64?
  mut receiver_user_id : Int64
  mut sender_user_id : Int64
  mut sender_name : String?
  mut url : String?
  mut variable : String?
  mut is_read : Int?
}

///|
let message_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "title": @moon_zod.string().max(255, msg="title 最多 255 位"),
  "content": @moon_zod.string().optional(),
  "msgType": @moon_zod.number().int(),
  "bizType": @moon_zod.string().max(64, msg="bizType 最多 64 位"),
  "bizId": @moon_zod.any().optional(),
  "receiverUserId": @moon_zod.any().optional(),
  "senderUserId": @moon_zod.any().optional(),
  "senderName": @moon_zod.string().max(64, msg="senderName 最多 64 位").optional(),
  "url": @moon_zod.string().max(255, msg="url 最多 255 位").optional(),
  "ext": @moon_zod.any().optional(),
  "isRead": @moon_zod.number().int().optional(),
})

///|
/// 从 Json 提取 Req
fn message_req_of(data : Json) -> MessageSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    title: @core.text_or(data, "title", ""),
    content: @core.get_text(data, "content"),
    // NOT NULL 列业务默认值（layering §7：缺省落 10=待办，MessageTypeEnum 首码）
    msg_type: @core.get_int(data, "msgType").unwrap_or(10),
    biz_type: @core.text_or(data, "bizType", ""),
    biz_id: @core.get_i64(data, "bizId"),
    receiver_user_id: @core.get_i64(data, "receiverUserId").unwrap_or(0L),
    sender_user_id: @core.get_i64(data, "senderUserId").unwrap_or(0L),
    sender_name: @core.get_text(data, "senderName"),
    url: @core.get_text(data, "url"),
    variable: Some(match @core.get_ext_string(data, "ext") {
      Some(s) => s
      None => "{}"
    }),
    is_read: @core.get_int(data, "isRead"),
  }
}

///|
pub fn message_parse_save(body : Json) -> MessageSaveReq raise @core.MldongError {
  match message_save_schema.parse(body) {
    Ok(data) => message_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidParam(errors[0].to_string())
  }
}

///|
pub fn message_parse_update(body : Json) -> MessageSaveReq raise @core.MldongError {
  let req = message_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("MessageID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct MessagePageReq {
  /// bizTypes 过滤（服务端自动补 appCode 前缀，boot2 同款）
  biz_types : Array[String]
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn message_parse_page(body : Json) -> MessagePageReq raise @core.MldongError {
  let page_num = @core.get_int(body, "pageNum").unwrap_or(1)
  let page_size = @core.get_int(body, "pageSize").unwrap_or(10)
  if page_num <= 0 || page_size <= 0 {
    raise @core.MldongError::InvalidInput("分页参数非法")
  }
  let biz_types : Array[String] = []
  match body {
    Object(map) =>
      match map.get("bizTypes") {
        Some(Array(items)) =>
          for it in items {
            match it {
              String(v) => biz_types.push(v)
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  {
    page_num,
    page_size,
    biz_types,
    m: @core.parse_m_params(body, exclude=["pageNum", "pageSize", "keywords", "searchKeys", "orderBy", "bizTypes"]),
    keywords: @core.text_or(body, "keywords", ""),
    search_keys: @core.text_or(body, "searchKeys", ""),
  }
}

///|
/// 出参装配：<Cls> → Json（camelCase；雪花 id 一律字符串化防 JS 精度丢失）
pub fn message_json(d : @entity.Message) -> Json {
  let obj : Json = {
    "id": d.id.to_string(),
    "title": Json::string(d.title),
    "content": jstr(d.content),
    "msgType": Json::number(d.msg_type.to_double()),
    "bizType": Json::string(d.biz_type),
    "bizId": jsnow(d.biz_id),
    "receiverUserId": d.receiver_user_id.to_string(),
    "senderUserId": d.sender_user_id.to_string(),
    "senderName": jstr(d.sender_name),
    "url": jstr(d.url),
    "isRead": jint(d.is_read),
    "createUser": jsnow(d.create_user),
    "createTime": jstr(d.create_time),
    "updateUser": jsnow(d.update_user),
    "updateTime": jstr(d.update_time),
    "isDeleted": jint(d.is_deleted),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("message_json 恒为 Object")
  }
  // ext 空不出键（UC-0426：'{}' 恒重写与 NULL 两态同判）
  match @core.ext_json_opt(d.variable) {
    Some(e) => { let _ = base.set("ext", e) }
    None => ()
  }
  Json::object(base)
}
