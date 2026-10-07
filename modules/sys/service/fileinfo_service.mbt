// sys_file_info 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait FileInfoService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.FileInfoSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.FileInfoSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.FileInfo raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.FileInfoPageReq) -> (Int, Array[@entity.FileInfo]) raise @core.MldongError
  /// 上传落盘 + 台账入库（boot2 upload 同位：路径 {base}/yyyyMM/{objectId}.{ext}，
  /// base 取 MLDONG_UPLOAD_PATH env 缺省 ./uploadfiles；返回 (row, url)）
  async fn upload_file(
    Self,
    @core.Ctx,
    filename : String,
    content : Bytes,
    content_type : String,
    object_type : String,
  ) -> @entity.FileInfo raise @core.MldongError
  /// 前端文件列表回查（boot2 AntUploadModel 同形：id/uid/name/url/status）
  async fn list_ant_by_ids(Self, @core.Ctx, Array[Int64]) -> Array[Json] raise @core.MldongError
  /// 分片上传初始化（boot2 initiateMultipartUpload 同位）：先落台账行，返回 (fileInfoId, uploadId)。
  /// url 在初始化时就写入记录（契约 UC-0604）；实现体见 fileinfo_multipart.mbt
  async fn initiate_multipart(
    Self,
    @core.Ctx,
    size : Int64,
    original_filename : String,
    content_type : String,
    object_type : String,
  ) -> (Int64, String) raise @core.MldongError
  /// 单枚分片落盘（boot2 uploadPart 同位：作用域只这一枚序号，不碰同会话其它分片）
  async fn upload_part(
    Self,
    @core.Ctx,
    file_info_id : Int64,
    part_number : Int,
    content : Bytes,
  ) -> Unit raise @core.MldongError
  /// 合并（boot2 completeMultipartUpload 同位）：按序号排序拼接 → 回写真实 size/size_info → 清扫暂存
  async fn complete_multipart(Self, @core.Ctx, Int64) -> @entity.FileInfo raise @core.MldongError
  /// 取消（boot2 abortMultipartUpload 同位）：清暂存 + 删台账行（契约"取消后删除记录与平台侧残留"）
  async fn abort_multipart(Self, @core.Ctx, Int64) -> Unit raise @core.MldongError
}

///|
/// 上传根目录（env 优先；boot2 sys_config UPLOAD_BASE_PATH / LOCAL_STORAGE_PATH 同位的 moon 简化）
pub fn upload_base_path() -> String {
  match @env.get_env_var("MLDONG_UPLOAD_PATH") {
    Some(v) => if v.is_empty() { "./uploadfiles" } else { v }
    None => "./uploadfiles"
  }
}

///|
pub(all) struct FileInfoServiceImpl[R, S] {
  dao : R
  /// 存储后端（FileStorage 端口）：本文件只管台账与业务规则，对象怎么放交给它
  storage : S
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn save(self, ctx, req) {
  let d : @entity.FileInfo = {
    id: @core.next_id(),
    url: req.url,
    size: req.size,
    size_info: req.size_info,
    filename: req.filename,
    original_filename: req.original_filename,
    base_path: req.base_path,
    path: req.path,
    ext: req.ext,
    content_type: req.content_type,
    platform: req.platform,
    th_url: req.th_url,
    th_filename: req.th_filename,
    th_size: req.th_size,
    th_size_info: req.th_size_info,
    th_content_type: req.th_content_type,
    object_id: req.object_id,
    object_type: req.object_type,
    attr: req.attr,
    create_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.FileInfo = {
    id: req.id,
    url: req.url,
    size: req.size,
    size_info: req.size_info,
    filename: req.filename,
    original_filename: req.original_filename,
    base_path: req.base_path,
    path: req.path,
    ext: req.ext,
    content_type: req.content_type,
    platform: req.platform,
    th_url: req.th_url,
    th_filename: req.th_filename,
    th_size: req.th_size,
    th_size_info: req.th_size_info,
    th_content_type: req.th_content_type,
    object_id: req.object_id,
    object_type: req.object_type,
    attr: req.attr,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn find_by_id(
  self,
  _ctx,
  id,
) {
  match self.dao.find_by_id(id) {
    Some(d) => d
    None => raise @core.MldongError::NotFound("数据不存在: " + id.to_string())
  }
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend FileInfoServiceImpl with FileInfoService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn upload_file(
  self,
  ctx,
  filename,
  content,
  content_type,
  object_type,
) {
  // 落盘交给存储端口（失败即回，不产半态台账）；命名/路径/url 口径见 LocalStorage
  let now = @core.now_str()
  let ym = now[0:4].to_owned() + now[5:7].to_owned()
  let object = self.storage.plan_object(filename, ym)
  self.storage.put_object(object, content)
  let ext = object.ext
  let stored = object.filename
  let dir = object.base_path
  let url = object.url
  let d : @entity.FileInfo = {
    id: @core.next_id(),
    url,
    size: Some(content.length().to_int64()),
    size_info: Some(size_info_of(content.length())),
    filename: Some(stored),
    original_filename: Some(filename),
    base_path: Some(dir),
    path: Some(object.path),
    ext: if ext.is_empty() { None } else { Some(ext) },
    content_type: if content_type.is_empty() { None } else { Some(content_type) },
    platform: Some("local"),
    th_url: None,
    th_filename: None,
    th_size: None,
    th_size_info: None,
    th_content_type: None,
    object_id: Some(object.object_id),
    object_type: if object_type.is_empty() { None } else { Some(object_type) },
    attr: None,
    create_time: Some(now),
    create_user: ctx.user_id,
    update_time: Some(now),
    update_user: ctx.user_id,
  }
  let _ = self.dao.insert(d)
  d
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn list_ant_by_ids(
  self,
  _ctx,
  ids,
) {
  let rows = self.dao.find_by_ids(ids)
  let arr : Array[Json] = []
  for f in rows {
    // boot2 AntUploadModel 同形（ant 设计上传组件回显）：status 恒 done
    arr.push({
      "id": Json::string(f.id.to_string()),
      "uid": Json::string(f.id.to_string()),
      "name": jstr_or(f.original_filename, jstr_or(f.filename, Json::string(""))),
      "url": Json::string(f.url),
      "status": Json::string("done"),
    })
  }
  arr
}

///|
pub extend FileInfoServiceImpl with FileInfoService::{
  upload_file,
  list_ant_by_ids,
  initiate_multipart,
  upload_part,
  complete_multipart,
  abort_multipart,
}

///|
/// 原文件名扩展名（小写；无扩展名空串）
fn filename_ext(filename : String) -> String {
  let mut dot = -1
  let mut i = 0
  for ch in filename {
    if ch.to_int() == 46 {
      dot = i
    }
    i = i + 1
  }
  if dot >= 0 && dot + 1 < filename.length() {
    filename[dot + 1:].to_owned().to_lower()
  } else {
    ""
  }
}

///|
/// 字节数人性化（boot2 sizeInfo 同位："12.3MB"）
fn size_info_of(n : Int) -> String {
  if n < 1024 {
    "\{n}B"
  } else if n < 1024 * 1024 {
    "\{n / 1024}KB"
  } else {
    let mb = n * 10 / (1024 * 1024)
    "\{mb / 10}.\{mb % 10}MB"
  }
}

///|
fn jstr_or(v : String?, default : Json) -> Json {
  match v {
    Some(s) => Json::string(s)
    None => default
  }
}
