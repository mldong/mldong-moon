// sys_dict_item 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn dictitem_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/dictItem/save", ["sys:dictItem:save"]))
    .rule(@guard.RouteRule::make("/sys/dictItem/remove", ["sys:dictItem:remove"]))
    .rule(@guard.RouteRule::make("/sys/dictItem/update", ["sys:dictItem:update"]))
    .rule(@guard.RouteRule::make("/sys/dictItem/detail", ["sys:dictItem:detail"]))
    .rule(@guard.RouteRule::make("/sys/dictItem/page", ["sys:dictItem:page"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.DictItemService] register_dictitem(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.dictitem_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.dictitem_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    let ctx = @web.ctx_of(request)
    @core.ok_data(@dto.dictitem_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.dictitem_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.dictitem_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/dictItem/save", save_handler)
  g.post(ctx, "/sys/dictItem/remove", remove_handler)
  g.post(ctx, "/sys/dictItem/update", update_handler)
  g.post(ctx, "/sys/dictItem/detail", detail_handler)
  g.post(ctx, "/sys/dictItem/page", page_handler)
}
