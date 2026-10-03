// sys_user 控制器 —— guard + 转发（校验在 dto）；URL 对齐 mldong 13 栈契约
// 权限码预留（guard 下一轮挂）：save=sys:user:save remove=sys:user:remove
// update=sys:user:update detail=sys:user:detail page=sys:user:page

///|
/// handler 统一包装：业务闭包（只许抛 MldongError）返回信封 Json 回 200；
/// 错误在这一层转信封（全局转换的骨架版，§6.6-1）
fn wrap(handle_body : async (@mb.Request) -> Json raise @core.MldongError) -> @mb.Handler {
  async fn(request, responder) {
    let body : Json = handle_body(request) catch {
      err => @core.fail_of(err)
    }
    responder.send_json(body, headers=[("Content-Type", "application/json; charset=utf-8")]) catch {
      _ => ()
    }
  }
}

///|
async fn json_body(request : @mb.Request) -> Json raise @core.MldongError {
  request.body.json() catch {
    _ => raise @core.MldongError::InvalidInput("请求体必须是合法 JSON")
  }
}

///|
fn ids_of(body : Json) -> Array[Int64] {
  let out : Array[Int64] = []
  match body {
    Object(map) =>
      match map.get("ids") {
        Some(Array(arr)) =>
          for v in arr {
            match v {
              Number(n, ..) => out.push(n.to_int64())
              String(s) =>
                // 雪花 id 前端按字符串回传（13 栈精度口径）
                try {
                  out.push(@string.parse_int64(s))
                } catch {
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  out
}

///|
pub fn[T : @svc.UserService] register(ctx : @mb.ModuleContext, svc : T) -> Unit raise {
  let save_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      let req = @dto.parse_save(json_body(request))
      let id = svc.save(req)
      @core.ok_data(Json::string(id.to_string()))
    },
  )
  let remove_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      svc.remove_by_ids(ids_of(json_body(request)))
      @core.ok_empty()
    },
  )
  let update_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      let req = @dto.parse_update(json_body(request))
      svc.update(req)
      @core.ok_empty()
    },
  )
  let detail_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      let body = json_body(request)
      // 雪花 id 兼容数字与字符串两种入参（字符串为准，防 JS 精度丢失）
      let id : Int64 = match @core.get_i64(body, "id") {
        Some(n) => n
        None => 0L
      }
      let u = svc.find_by_id(id)
      @core.ok_data(@dto.user_json(u))
    },
  )
  let page_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      let req = @dto.parse_page(json_body(request))
      let (total, rows) = svc.page(req)
      let arr : Array[Json] = []
      for u in rows {
        arr.push(@dto.user_json(u))
      }
      @core.ok_page(req.page_num, req.page_size, total, arr)
    },
  )
  ctx.post("/sys/user/save", save_handler) catch {
    e => raise e
  }
  ctx.post("/sys/user/remove", remove_handler) catch {
    e => raise e
  }
  ctx.post("/sys/user/update", update_handler) catch {
    e => raise e
  }
  ctx.post("/sys/user/detail", detail_handler) catch {
    e => raise e
  }
  ctx.post("/sys/user/page", page_handler) catch {
    e => raise e
  }

}
