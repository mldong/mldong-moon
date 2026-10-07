// sys_file_info 的分片上传腿 —— 契约 UC-0604/0605（boot2 FileInfoController 那四条端点的 moon 同位）。
// 与 fileinfo_service.mbt 同包：那边管"台账怎么写"，这里管"分片会话的台账形状 + 四个业务方法"，
// 真正碰磁盘的部分在 file_storage.mbt 的 FileStorage 端口里（换云存储不改本文件）。

///|
/// 分片会话台账在 `sys_file_info.attr` 里的形状：
/// `{"uploadId":"<会话号>","parts":"1,2,3"}`
/// —— 这张表**没有 upload_id 列、也没有分片清单列**：boot2 把会话号交给 x-file-storage 的 attr，
/// fastapi 本地版同样写 attr={"uploadId":…}，moon 沿用同策，不加 DDL。
/// parts 只记序号（到达序）：合并时排序后交端口，真实字节数由合并结果回写。
fn multipart_attr(upload_id : String, parts : Array[Int]) -> String {
  let texts : Array[String] = []
  for n in parts {
    texts.push(n.to_string())
  }
  "{\"uploadId\":\"" + upload_id + "\",\"parts\":\"" + texts.join(",") + "\"}"
}

///|
fn multipart_upload_id(attr : String?) -> String? {
  @core.get_text(@core.parse_ext(attr), "uploadId")
}

///|
fn multipart_parts(attr : String?) -> Array[Int] {
  let out : Array[Int] = []
  match @core.get_text(@core.parse_ext(attr), "parts") {
    Some(text) =>
      for piece in text.split(",") {
        let t = piece.trim()
        if !t.is_empty() {
          try {
            out.push(@string.parse_int(t))
          } catch {
            _ => ()
          }
        }
      }
    None => ()
  }
  out
}

///|
/// 台账行 → 存储对象：合并/清理要按同一套路径规则找回对象位置，字段全取自 initiate 落的行
fn stored_of_row(d : @entity.FileInfo) -> StoredObject {
  let need = fn(opt : String?, what : String) -> String {
    match opt {
      Some(v) => v
      None => abort("分片台账行缺 " + what + "（initiate 必写全）")
    }
  }
  {
    object_id: need(d.object_id, "object_id"),
    ext: match d.ext { Some(v) => v ; None => "" },
    filename: need(d.filename, "filename"),
    base_path: need(d.base_path, "base_path"),
    path: need(d.path, "path"),
    url: d.url,
  }
}

///|
/// 按 id 取行，取不到即业务失败（boot2 三处都是"文件信息不存在"同档）
async fn[R : @dao.FileInfoDao] must_find_file_info(
  dao : R,
  id : Int64,
) -> @entity.FileInfo raise @core.MldongError {
  match dao.find_by_id(id) {
    Some(d) => d
    None => raise @core.MldongError::NotFound("文件信息不存在: " + id.to_string())
  }
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn initiate_multipart(
  self,
  ctx,
  size,
  original_filename,
  content_type,
  object_type,
) {
  if original_filename.is_empty() {
    raise @core.MldongError::InvalidParam("originalFilename 不能为空")
  }
  if !self.storage.is_support_multipart() {
    raise @core.MldongError::InvalidParam("不支持手动分片上传")
  }
  let now = @core.now_str()
  let ym = now[0:4].to_owned() + now[5:7].to_owned()
  let object = self.storage.plan_object(original_filename, ym)
  let upload_id = self.storage.initiate_multipart(object)
  let d : @entity.FileInfo = {
    id: @core.next_id(),
    // url 初始化即写（契约 UC-0604：本地存储有确定性地址，对齐 boot4）
    url: object.url,
    size: Some(size),
    size_info: Some(size_info_of(size.to_int())),
    filename: Some(object.filename),
    original_filename: Some(original_filename),
    base_path: Some(object.base_path),
    path: Some(object.path),
    ext: if object.ext.is_empty() { None } else { Some(object.ext) },
    content_type: if content_type.is_empty() { None } else { Some(content_type) },
    platform: Some("local"),
    th_url: None,
    th_filename: None,
    th_size: None,
    th_size_info: None,
    th_content_type: None,
    object_id: Some(object.object_id),
    object_type: if object_type.is_empty() { None } else { Some(object_type) },
    attr: Some(multipart_attr(upload_id, [])),
    create_time: Some(now),
    create_user: ctx.user_id,
    update_time: Some(now),
    update_user: ctx.user_id,
  }
  let _ = self.dao.insert(d)
  (d.id, upload_id)
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn upload_part(
  self,
  ctx,
  file_info_id,
  part_number,
  content,
) {
  if part_number <= 0 {
    raise @core.MldongError::InvalidParam("partNumber 必须从 1 起")
  }
  let d = must_find_file_info(self.dao, file_info_id)
  let upload_id = match multipart_upload_id(d.attr) {
    Some(v) => v
    None => raise @core.MldongError::InvalidParam("未找到上传ID")
  }
  self.storage.put_part(upload_id, part_number, content)
  // 台账只在"这枚序号之前没记过"时改行：重写同一枚时盘已覆盖，清单不该长出两条
  let parts = multipart_parts(d.attr)
  let mut seen = false
  for n in parts {
    if n == part_number {
      seen = true
    }
  }
  if !seen {
    parts.push(part_number)
    let up : @entity.FileInfo = {
      ..d,
      attr: Some(multipart_attr(upload_id, parts)),
      update_time: Some(@core.now_str()),
      update_user: ctx.user_id,
    }
    self.dao.update(up)
  }
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn complete_multipart(
  self,
  ctx,
  file_info_id,
) {
  let d = must_find_file_info(self.dao, file_info_id)
  let upload_id = match multipart_upload_id(d.attr) {
    Some(v) => v
    None => raise @core.MldongError::InvalidParam("未找到上传ID")
  }
  // 契约 UC-0605"服务端排序合并"：清单是到达序，必须按序号重排后再交端口拼
  let parts = multipart_parts(d.attr)
  parts.sort()
  if parts.is_empty() {
    raise @core.MldongError::Business("没有可合并的分片，请先上传分片")
  }
  let merged = self.storage.merge_parts(upload_id, stored_of_row(d), parts)
  self.storage.discard_parts(upload_id)
  // 回写**真实字节数**（initiate 落的是客户端声明值，不可信），size_info 同批改
  let up : @entity.FileInfo = {
    ..d,
    size: Some(merged),
    size_info: Some(size_info_of(merged.to_int())),
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
  }
  self.dao.update(up)
  up
}

///|
pub impl[R : @dao.FileInfoDao, S : FileStorage] FileInfoService for FileInfoServiceImpl[R, S] with fn abort_multipart(
  self,
  _ctx,
  file_info_id,
) {
  let d = must_find_file_info(self.dao, file_info_id)
  match multipart_upload_id(d.attr) {
    Some(upload_id) => {
      self.storage.discard_parts(upload_id)
      // 已合并过再取消的极端顺序：最终文件也清掉（remove_object 对不存在的文件静默）
      self.storage.remove_object(stored_of_row(d))
    }
    None => ()
  }
  self.dao.remove_by_ids([file_info_id])
}
