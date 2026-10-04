// dev_schema_field 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn schemafield_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/dev/schemaField/save", ["dev:schemaField:save"]))
    .rule(@guard.RouteRule::make("/dev/schemaField/remove", ["dev:schemaField:remove"]))
    .rule(@guard.RouteRule::make("/dev/schemaField/update", ["dev:schemaField:update"]))
    .rule(@guard.RouteRule::make("/dev/schemaField/detail", ["dev:schemaField:detail"]))
    .rule(@guard.RouteRule::make("/dev/schemaField/page", ["dev:schemaField:page"]))
    .rule(@guard.RouteRule::make("/dev/schemaField/updateSort", ["dev:schemaField:updateSort"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.SchemaFieldService] register_schemafield(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.schemafield_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.schemafield_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    let ctx = @web.ctx_of(request)
    @core.ok_data(@dto.schemafield_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.schemafield_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.schemafield_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/dev/schemaField/save", save_handler)
  g.post(ctx, "/dev/schemaField/remove", remove_handler)
  g.post(ctx, "/dev/schemaField/update", update_handler)
  g.post(ctx, "/dev/schemaField/detail", detail_handler)
  // 拖拽排序（boot2 updateSort 同算法；UpdateSortParam{schemaId,dragRowId,hoverRowId}）
  let update_sort_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let schema_id = match @core.get_i64(body, "schemaId") {
      Some(n) => n
      None => 0L
    }
    let drag_id = match @core.get_i64(body, "dragRowId") {
      Some(n) => n
      None => 0L
    }
    let hover_id = match @core.get_i64(body, "hoverRowId") {
      Some(n) => n
      None => 0L
    }
    if schema_id <= 0L || drag_id <= 0L || hover_id <= 0L {
      raise @core.MldongError::InvalidInput("schemaId/dragRowId/hoverRowId 不能为空")
    }
    svc.update_sort(ctx, schema_id, drag_id, hover_id)
    @core.ok_empty()
  })
  g.post(ctx, "/dev/schemaField/page", page_handler)
  g.post(ctx, "/dev/schemaField/updateSort", update_sort_handler)
}
