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
            @core.fail(99990001, "multipart/form-data 文件域缺失"),
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
  g.post(ctx, "/sys/fileInfo/upload", upload_handler)
  g.post(ctx, "/sys/fileInfo/getFileInfoByIds", by_ids_handler)
  g.post(ctx, "/sys/fileInfo/page", page_handler)
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
/// 最小 multipart/form-data 解析：取第一个带 filename 的文件域。
/// 返回 (原文件名, 内容字节, part 的 Content-Type)；无文件域 None。
/// 形状假设（浏览器/urllib 标准体）：boundary 行 --{b}\r\n、头块 \r\n\r\n 结束、尾标 --{b}--。
fn multipart_parse(raw : Bytes, content_type : String) -> (String, Bytes, String)? {
  // boundary = content-type 里 boundary= 后到行尾（可带引号）
  let bidx = find_substring(content_type, "boundary=")
  if bidx < 0 {
    return None
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
    return None
  }
  let bmark : Bytes = bytes_of("--" + boundary)
  let n = raw.length()
  // 逐段扫描 --boundary
  let mut i = 0
  while i < n {
    // 找下一个 boundary 起点
    let start = find_bytes(raw[:], bmark[:], i)
    if start < 0 {
      return None
    }
    let mut p = start + bmark.length()
    // 终止标 --boundary-- → 结束
    if p + 1 < n && raw[p] == b'-' && raw[p + 1] == b'-' {
      return None
    }
    // 跳过 \r\n
    if p + 1 < n && raw[p] == b'\r' && raw[p + 1] == b'\n' {
      p = p + 2
    }
    // 头块到 \r\n\r\n
    let head_end = find_bytes(raw, bytes_of("\r\n\r\n"), p)
    if head_end < 0 {
      return None
    }
    let head = bytes_text(raw[p:head_end])
    // 体到下一个 --boundary（体尾 \r\n 属分隔）
    let next = find_bytes(raw[:], bmark[:], head_end + 4)
    if next < 0 {
      return None
    }
    let mut body_end = next
    if body_end - 2 >= head_end + 4 && raw[body_end - 2] == b'\r' && raw[body_end - 1] == b'\n' {
      body_end = body_end - 2
    }
    // 有 filename 的域才算文件
    let fname = header_param(head, "filename")
    match fname {
      Some(f) => {
        let ctype = match header_param(head, "Content-Type") {
          Some(t) => t
          None => match header_param(head, "content-type") {
            Some(t) => t
            None => ""
          }
        }
        return Some((f, raw[head_end + 4:body_end].to_owned(), ctype))
      }
      None => {
        // 普通域（objectType 等）跳过，继续下一段
        i = next
        continue
      }
    }
  }
  None
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
