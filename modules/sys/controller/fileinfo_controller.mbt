// sys_file_info 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn fileinfo_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/fileInfo/save", ["sys:fileInfo:save"]))
    .rule(@guard.RouteRule::make("/sys/fileInfo/remove", ["sys:fileInfo:remove"]))
    .rule(@guard.RouteRule::make("/sys/fileInfo/update", ["sys:fileInfo:update"]))
    .rule(@guard.RouteRule::make("/sys/fileInfo/detail", ["sys:fileInfo:detail"]))
    .rule(@guard.RouteRule::make("/sys/fileInfo/page", ["sys:fileInfo:page"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.FileInfoService] register_fileinfo(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.fileinfo_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.fileinfo_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    let ctx = @web.ctx_of(request)
    @core.ok_data(@dto.fileinfo_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.fileinfo_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.fileinfo_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/fileInfo/save", save_handler)
  g.post(ctx, "/sys/fileInfo/remove", remove_handler)
  g.post(ctx, "/sys/fileInfo/update", update_handler)
  g.post(ctx, "/sys/fileInfo/detail", detail_handler)
  // 上传（multipart/form-data：boot2 MultipartFile 同位；x-file-storage local-plus 的
  // moon 简化——本地盘直写，url 形 /uploadfiles/yyyyMM/objectId.ext）
  let upload_handler : @mb.Handler = async fn(request, responder) {
    let ctx = @web.ctx_of(request)
    let raw = request.body.binary() catch {
      _ => Bytes::from_array([])
    }
    try {
      let content_type = header_of(request, "Content-Type")
      let parsed = multipart_parse(raw, content_type)
      let (filename, content, part_type) = match parsed {
        Some(v) => v
        None => {
          responder.send_json(
            @core.fail(99999999, "multipart/form-data 文件域缺失"),
            headers=[("Content-Type", "application/json; charset=utf-8")],
          ) catch {
            _ => ()
          }
          return
        }
      }
      let object_type = query_of(request, "objectType")
      let row = svc.upload_file(ctx, filename, content, part_type, object_type)
      let body : Json = {
        // boot2 返回 {fullUrl, url, fileInfoId}：fullUrl 无域名配置时与 url 同值
        "url": Json::string(row.url),
        "fullUrl": Json::string(row.url),
        "fileInfoId": Json::string(row.id.to_string()),
      }
      responder.send_json(
        @core.ok_data(body),
        headers=[("Content-Type", "application/json; charset=utf-8")],
      ) catch {
        _ => ()
      }
    } catch {
      e => {
        responder.send_json(
          { "code": e.code(), "msg": e.message(), "data": Json::null() },
          headers=[("Content-Type", "application/json; charset=utf-8")],
        ) catch {
          _ => ()
        }
      }
    }
  }
  // 前端文件列表回查（fileInfoIds 逗号分隔串）
  let by_ids_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let raw = @core.text_or(@web.json_body(request), "fileInfoIds", "")
    let ids = @core.get_i64_array(@web.json_body(request), "fileInfoIds")
    // runner 传逗号分隔串（get_i64_array 只吃数组）——手工切串兼容双形态
    let list = if raw.contains(",") || (raw != "" && ids.is_empty()) {
      let arr : Array[Int64] = []
      for part in raw.split(",") {
        let piece = part.trim().to_owned()
        if piece.is_empty() {
          continue
        }
        try {
          arr.push(@string.parse_int64(piece))
        } catch {
          _ => ()
        }
      }
      arr
    } else {
      ids
    }
    @core.ok_data(Json::array(svc.list_ant_by_ids(ctx, list)))
  })
  // ── 分片上传四件套（契约 UC-0604/0605）──
  // 鉴权面与参考实现一致：boot2 那四条只有 @PostMapping、fastapi 也没有 @SaCheckPermission，
  // 即**仅登录、无权限码**——main 已关推导，未列进 policy 的端点正好就是这个档位。
  let initiate_multipart_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let (file_info_id, upload_id) = svc.initiate_multipart(
      ctx,
      @core.get_i64(body, "size").unwrap_or(0L),
      @core.text_or(body, "originalFilename", ""),
      @core.text_or(body, "contentType", ""),
      @core.text_or(body, "objectType", ""),
    )
    // fileInfoId 一律字符串（全局约定 §5：雪花 id 出数字面量会在前端 JSON.parse 丢精度）
    let out : Json = {
      "fileInfoId": Json::string(file_info_id.to_string()),
      "uploadId": Json::string(upload_id),
    }
    @core.ok_data(out)
  })
  let upload_part_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let raw = request.body.binary() catch {
      _ => Bytes::from_array([])
    }
    let parts = multipart_parts(raw, header_of(request, "Content-Type"))
    match file_part_of(parts) {
      None => raise @core.MldongError::InvalidParam("multipart/form-data 文件域缺失")
      Some(fp) => {
        // partNumber/fileInfoId 是**表单文本域**（boot2 用 @RequestParam、fastapi 用 Form(...)）
        let part_number = field_int(parts, "partNumber")
        let file_info_id = field_int64(parts, "fileInfoId")
        svc.upload_part(ctx, file_info_id, part_number, fp.content)
      }
    }
    @core.ok_empty()
  })
  let complete_multipart_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let d = svc.complete_multipart(ctx, need_file_info_id(@web.json_body(request)))
    let out : Json = {
      // boot2 出口三键：fullUrl（带域名包装）/url/fileInfoId；moon 无域名配置，fullUrl 与 url 同值
      "fullUrl": Json::string(d.url),
      "url": Json::string(d.url),
      "fileInfoId": Json::string(d.id.to_string()),
    }
    @core.ok_data(out)
  })
  let abort_multipart_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.abort_multipart(ctx, need_file_info_id(@web.json_body(request)))
    @core.ok_empty()
  })
  g.post(ctx, "/sys/fileInfo/upload", upload_handler)
  g.post(ctx, "/sys/fileInfo/getFileInfoByIds", by_ids_handler)
  g.post(ctx, "/sys/fileInfo/page", page_handler)
  g.post(ctx, "/sys/fileInfo/initiateMultipartUpload", initiate_multipart_handler)
  g.post(ctx, "/sys/fileInfo/uploadPart", upload_part_handler)
  g.post(ctx, "/sys/fileInfo/completeMultipartUpload", complete_multipart_handler)
  g.post(ctx, "/sys/fileInfo/abortMultipartUpload", abort_multipart_handler)
}

///|
/// complete/abort 的 fileInfoId：字符串/数字双形态都收（全局约定 §5 入参容错），缺/非法即参数错
fn need_file_info_id(body : Json) -> Int64 raise @core.MldongError {
  match @core.get_i64(body, "fileInfoId") {
    Some(v) if v > 0L => v
    _ => raise @core.MldongError::InvalidParam("fileInfoId 不能为空")
  }
}

///|
fn header_of(request : @mb.Request, name : String) -> String {
  match request.headers.get(name) {
    Some(v) => v.to_owned()
    None => ""
  }
}

///|
fn query_of(request : @mb.Request, name : String) -> String {
  match request.query().get(name) {
    Some(v) => v
    None => ""
  }
}

///|
/// multipart/form-data 的一段：文本域只有 name，文件域另有 filename/content_type
priv struct MPart {
  name : String
  filename : String
  content_type : String
  content : Bytes
}

///|
/// 单个扫描器吃下**全部**分段（形状假设同旧版：boundary 行 --{b}\r\n、头块 \r\n\r\n 结束、
/// 尾标 --{b}--）。uploadPart 要同时拿文件域与 partNumber/fileInfoId 文本域，
/// upload 只要文件域——两边都走这里，不再养第二份 walker。
fn multipart_parts(raw : Bytes, content_type : String) -> Array[MPart] {
  let out : Array[MPart] = []
  let bidx = find_substring(content_type, "boundary=")
  if bidx < 0 {
    return out
  }
  let mut boundary = content_type[bidx + 9:].to_owned()
  if boundary.has_prefix("\"") {
    boundary = boundary[1:].to_owned()
    let q = find_substring(boundary, "\"")
    if q >= 0 {
      boundary = boundary[1:q].to_owned()
    }
  } else {
    let semi = find_substring(boundary, ";")
    if semi >= 0 {
      boundary = boundary[:semi].to_owned()
    }
  }
  if boundary.is_empty() {
    return out
  }
  let bmark : Bytes = bytes_of("--" + boundary)
  let n = raw.length()
  let mut i = 0
  while i < n {
    let start_at = find_bytes(raw[:], bmark[:], i)
    if start_at < 0 {
      return out
    }
    let mut p = start_at + bmark.length()
    if p + 1 < n && raw[p] == b'-' && raw[p + 1] == b'-' {
      return out
    }
    if p + 1 < n && raw[p] == b'\r' && raw[p + 1] == b'\n' {
      p = p + 2
    }
    let head_end = find_bytes(raw, bytes_of("\r\n\r\n"), p)
    if head_end < 0 {
      return out
    }
    let next = find_bytes(raw[:], bmark[:], head_end + 4)
    if next < 0 {
      return out
    }
    let mut body_end = next
    if body_end - 2 >= head_end + 4 && raw[body_end - 2] == b'\r' && raw[body_end - 1] == b'\n' {
      body_end = body_end - 2
    }
    let head = bytes_text(raw[p:head_end])
    out.push(MPart::{
      name: match header_param(head, "name") { Some(v) => v ; None => "" },
      filename: match header_param(head, "filename") { Some(v) => v ; None => "" },
      content_type: match header_param(head, "Content-Type") {
        Some(v) => v
        None => match header_param(head, "content-type") { Some(v) => v ; None => "" }
      },
      content: raw[head_end + 4:body_end].to_owned(),
    })
    i = next
  }
  out
}

///|
/// 第一个带 filename 的分段（普通上传/分片上传取文件内容都靠它）
fn file_part_of(parts : Array[MPart]) -> MPart? {
  let mut hit : MPart? = None
  for p in parts {
    if !p.filename.is_empty() && hit is None {
      hit = Some(p)
    }
  }
  hit
}

///|
fn field_text(parts : Array[MPart], name : String) -> String {
  let mut out = ""
  for p in parts {
    if p.name == name && p.filename.is_empty() && out.is_empty() {
      out = bytes_text(p.content[:])
    }
  }
  out
}

///|
fn field_int(parts : Array[MPart], name : String) -> Int raise @core.MldongError {
  let text = field_text(parts, name)
  if text.is_empty() {
    raise @core.MldongError::InvalidParam("表单字段缺失: " + name)
  }
  try {
    @string.parse_int(text)
  } catch {
    _ => raise @core.MldongError::InvalidParam("表单字段非整数: " + name)
  }
}

///|
fn field_int64(parts : Array[MPart], name : String) -> Int64 raise @core.MldongError {
  let text = field_text(parts, name)
  if text.is_empty() {
    raise @core.MldongError::InvalidParam("表单字段缺失: " + name)
  }
  try {
    @string.parse_int64(text)
  } catch {
    _ => raise @core.MldongError::InvalidParam("表单字段非整数: " + name)
  }
}

///|
/// 兼容旧出口：只取文件域三元组（原文件名, 内容, part 的 Content-Type）
fn multipart_parse(raw : Bytes, content_type : String) -> (String, Bytes, String)? {
  match file_part_of(multipart_parts(raw, content_type)) {
    Some(p) => Some((p.filename, p.content, p.content_type))
    None => None
  }
}

///|
fn bytes_of(s : String) -> Bytes {
  // 调用方只喂 ASCII（boundary/CRLF/双 CRLF）——逐字符取低字节装配
  let buf : Array[Byte] = []
  for ch in s {
    buf.push((ch.to_int() & 0xFF).to_byte())
  }
  Bytes::from_iter(buf.iter())
}

///|
fn bytes_text(v : BytesView) -> String {
  @utf8.decode_lossy(v)
}

///|
/// 字节序列查找（朴素算法；上传体量小够用）
fn find_bytes(raw : BytesView, pat : BytesView, from : Int) -> Int {
  let n = raw.length()
  let m = pat.length()
  if m == 0 || n < m {
    return -1
  }
  let mut i = from
  while i <= n - m {
    let mut ok = true
    let mut j = 0
    while j < m {
      if raw[i + j] != pat[j] {
        ok = false
        break
      }
      j = j + 1
    }
    if ok {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn find_substring(s : String, sub : String) -> Int {
  let n = s.length()
  let m = sub.length()
  if m == 0 || n < m {
    return -1
  }
  let mut i = 0
  while i <= n - m {
    if s[i:i + m].to_owned() == sub {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 头块里取 form 参数（name="x" / filename="x" / Content-Type: y 三种形状）
fn header_param(head : String, key : String) -> String? {
  // 形状1：key="value"（name/filename）
  let k = key + "=\""
  let i = find_substring(head, k)
  if i >= 0 {
    let rest = head[i + k.length():].to_owned()
    let j = find_substring(rest, "\"")
    if j >= 0 {
      return Some(rest[:j].to_owned())
    }
  }
  // 形状2：key: value（Content-Type）
  let k2 = key + ": "
  let i2 = find_substring(head, k2)
  if i2 >= 0 {
    let rest = head[i2 + k2.length():].to_owned()
    let j = find_substring(rest, "\r")
    if j >= 0 {
      return Some(rest[:j].to_owned())
    }
    return Some(rest)
  }
  None
}
