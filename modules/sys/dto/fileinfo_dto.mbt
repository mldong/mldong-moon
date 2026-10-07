// sys_file_info 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct FileInfoSaveReq {
  mut id : Int64
  mut url : String
  mut size : Int64?
  mut size_info : String?
  mut filename : String?
  mut original_filename : String?
  mut base_path : String?
  mut path : String?
  mut ext : String?
  mut content_type : String?
  mut platform : String?
  mut th_url : String?
  mut th_filename : String?
  mut th_size : Int64?
  mut th_size_info : String?
  mut th_content_type : String?
  mut object_id : String?
  mut object_type : String?
  mut attr : String?
}

///|
let fileinfo_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "url": @moon_zod.string().max(64, msg="url 最多 64 位"),
  "size": @moon_zod.any().optional(),
  "sizeInfo": @moon_zod.string().max(64, msg="sizeInfo 最多 64 位").optional(),
  "filename": @moon_zod.string().max(255, msg="filename 最多 255 位").optional(),
  "originalFilename": @moon_zod.string().max(255, msg="originalFilename 最多 255 位").optional(),
  "basePath": @moon_zod.string().max(64, msg="basePath 最多 64 位").optional(),
  "path": @moon_zod.string().max(64, msg="path 最多 64 位").optional(),
  "ext": @moon_zod.string().max(32, msg="ext 最多 32 位").optional(),
  "contentType": @moon_zod.string().max(100, msg="contentType 最多 100 位").optional(),
  "platform": @moon_zod.string().max(32, msg="platform 最多 32 位").optional(),
  "thUrl": @moon_zod.string().max(255, msg="thUrl 最多 255 位").optional(),
  "thFilename": @moon_zod.string().max(255, msg="thFilename 最多 255 位").optional(),
  "thSize": @moon_zod.any().optional(),
  "thSizeInfo": @moon_zod.string().max(64, msg="thSizeInfo 最多 64 位").optional(),
  "thContentType": @moon_zod.string().max(32, msg="thContentType 最多 32 位").optional(),
  "objectId": @moon_zod.string().max(32, msg="objectId 最多 32 位").optional(),
  "objectType": @moon_zod.string().max(32, msg="objectType 最多 32 位").optional(),
  "attr": @moon_zod.string().optional(),
})

///|
/// 从 Json 提取 Req
fn fileinfo_req_of(data : Json) -> FileInfoSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    url: @core.text_or(data, "url", ""),
    size: @core.get_i64(data, "size"),
    size_info: @core.get_text(data, "sizeInfo"),
    filename: @core.get_text(data, "filename"),
    original_filename: @core.get_text(data, "originalFilename"),
    base_path: @core.get_text(data, "basePath"),
    path: @core.get_text(data, "path"),
    ext: @core.get_text(data, "ext"),
    content_type: @core.get_text(data, "contentType"),
    platform: @core.get_text(data, "platform"),
    th_url: @core.get_text(data, "thUrl"),
    th_filename: @core.get_text(data, "thFilename"),
    th_size: @core.get_i64(data, "thSize"),
    th_size_info: @core.get_text(data, "thSizeInfo"),
    th_content_type: @core.get_text(data, "thContentType"),
    object_id: @core.get_text(data, "objectId"),
    object_type: @core.get_text(data, "objectType"),
    attr: @core.get_text(data, "attr"),
  }
}

///|
pub fn fileinfo_parse_save(body : Json) -> FileInfoSaveReq raise @core.MldongError {
  match fileinfo_save_schema.parse(body) {
    Ok(data) => fileinfo_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidParam(errors[0].to_string())
  }
}

///|
pub fn fileinfo_parse_update(body : Json) -> FileInfoSaveReq raise @core.MldongError {
  let req = fileinfo_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("FileInfoID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct FileInfoPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn fileinfo_parse_page(body : Json) -> FileInfoPageReq raise @core.MldongError {
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
pub fn fileinfo_json(d : @entity.FileInfo) -> Json {
  {
    "id": d.id.to_string(),
    "url": Json::string(d.url),
    "size": jsnow(d.size),
    "sizeInfo": jstr(d.size_info),
    "filename": jstr(d.filename),
    "originalFilename": jstr(d.original_filename),
    "basePath": jstr(d.base_path),
    "path": jstr(d.path),
    "ext": jstr(d.ext),
    "contentType": jstr(d.content_type),
    "platform": jstr(d.platform),
    "thUrl": jstr(d.th_url),
    "thFilename": jstr(d.th_filename),
    "thSize": jsnow(d.th_size),
    "thSizeInfo": jstr(d.th_size_info),
    "thContentType": jstr(d.th_content_type),
    "objectId": jstr(d.object_id),
    "objectType": jstr(d.object_type),
    "attr": jstr(d.attr),
    "createTime": jstr(d.create_time),
    "createUser": jsnow(d.create_user),
    "updateTime": jstr(d.update_time),
    "updateUser": jsnow(d.update_user),
  }
}
