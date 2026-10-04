// sys_post 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn post_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/post/save", ["sys:post:save"]))
    .rule(@guard.RouteRule::make("/sys/post/remove", ["sys:post:remove"]))
    .rule(@guard.RouteRule::make("/sys/post/update", ["sys:post:update"]))
    .rule(@guard.RouteRule::make("/sys/post/detail", ["sys:post:detail"]))
    .rule(@guard.RouteRule::make("/sys/post/page", ["sys:post:page"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.PostService] register_post(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let op_user = @web.user_id_of(request)
    let id = svc.save(@dto.post_parse_save(@web.json_body(request)), op_user)
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    svc.remove_by_ids(@core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let op_user = @web.user_id_of(request)
    svc.update(@dto.post_parse_update(@web.json_body(request)), op_user)
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    @core.ok_data(@dto.post_json(svc.find_by_id(id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let req = @dto.post_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.post_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/post/save", save_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/post/remove", remove_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/post/update", update_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/post/detail", detail_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/post/page", page_handler) catch {
    e => raise e
  }
}
