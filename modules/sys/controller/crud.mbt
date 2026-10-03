// 控制层通用件 —— 五端点 CRUD 的路由骨架抽离（user/role 双实体对照后的公共面）：
//   wrap（错误转信封）/ json_body / ids_of / CrudHandlers + register_crud
// 每实体 controller 只剩：构造 CrudHandlers（parse + 调 service + 装配出参）+ 一行注册；
// 差异点全部参数化：入参 parse（dto）、service 调用、出参装配、page 返回行类型（单表/join 各异）

///|
/// handler 统一包装：业务闭包（只许抛 MldongError）返回信封 Json 回 200
pub fn wrap(handle_body : async (@mb.Request) -> Json raise @core.MldongError) -> @mb.Handler {
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
/// 读 JSON 请求体（非法 → 99990001）
pub async fn json_body(request : @mb.Request) -> Json raise @core.MldongError {
  request.body.json() catch {
    _ => raise @core.MldongError::InvalidInput("请求体必须是合法 JSON")
  }
}

///|
/// 提取 ids 数组（雪花 id 兼容字符串/数字两种形态；字符串为准防 JS 精度丢失）
pub fn ids_of(body : Json) -> Array[Int64] {
  let out : Array[Int64] = []
  match body {
    Object(map) =>
      match map.get("ids") {
        Some(Array(arr)) =>
          for v in arr {
            match v {
              Number(n, ..) => out.push(n.to_int64())
              String(s) =>
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
/// 五端点处理闭包集（每实体一份；全部吃原始 body Json，校验在 dto 层）
pub(all) struct CrudHandlers {
  /// save：body → data 部分（如新 id 的字符串形态）
  save : async (Json) -> Json raise @core.MldongError
  /// update：body → 成功回 ok_empty
  update : async (Json) -> Unit raise @core.MldongError
  /// remove：body → 成功回 ok_empty（ids 从 body 取）
  remove : async (Json) -> Unit raise @core.MldongError
  /// detail：body → data 部分（单行出参）
  detail : async (Json) -> Json raise @core.MldongError
  /// page：body → (pageNum, pageSize, total, rows)
  page : async (Json) -> (Int, Int, Int, Array[Json]) raise @core.MldongError
}

///|
/// 通用五端点注册：POST {prefix}/save|remove|update|detail|page
/// （URL 规范对齐 13 栈；权限码由 guard 层后续按前缀+action 推导）
pub fn register_crud(ctx : @mb.ModuleContext, prefix : String, h : CrudHandlers) -> Unit raise {
  // save/detail 返回裸 data，信封在这里统一包（CrudHandlers 只管产出 data 部分）
  let save_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      @core.ok_data((h.save)(json_body(request)))
    },
  )
  let remove_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      (h.remove)(json_body(request))
      @core.ok_empty()
    },
  )
  let update_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      (h.update)(json_body(request))
      @core.ok_empty()
    },
  )
  let detail_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      @core.ok_data((h.detail)(json_body(request)))
    },
  )
  let page_handler : @mb.Handler = wrap(
    async fn(request) -> Json raise @core.MldongError {
      let (page_num, page_size, total, rows) = (h.page)(json_body(request))
      @core.ok_page(page_num, page_size, total, rows)
    },
  )
  ctx.post("\{prefix}/save", save_handler) catch {
    e => raise e
  }
  ctx.post("\{prefix}/remove", remove_handler) catch {
    e => raise e
  }
  ctx.post("\{prefix}/update", update_handler) catch {
    e => raise e
  }
  ctx.post("\{prefix}/detail", detail_handler) catch {
    e => raise e
  }
  ctx.post("\{prefix}/page", page_handler) catch {
    e => raise e
  }
}
