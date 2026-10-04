// sys_message 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn message_policy() -> @guard.RoutePolicy {
  // boot2 对齐：仅 save/update 有 @SaCheckPermission；remove/detail/page/setRead/
  // 未读计数无注解 = 仅登录（runner UC-0501 注释同口径："消息 page 为无权限接口"）
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/message/save", ["sys:message:save"]))
    .rule(@guard.RouteRule::make("/sys/message/update", ["sys:message:update"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.MessageService] register_message(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.message_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.message_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    let ctx = @web.ctx_of(request)
    @core.ok_data(@dto.message_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.message_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.message_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  // 置已读（ids 可空=全部已读，仅本人消息）
  let set_read_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.set_read(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  // 未读计数
  let unread_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    @core.ok_data(Json::number(svc.unread_count(ctx).to_double()))
  })
  // 未读按 biz_type 分组
  let unread_group_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    @core.ok_data(Json::array(svc.unread_count_group(ctx)))
  })
  g.post(ctx, "/sys/message/save", save_handler)
  g.post(ctx, "/sys/message/remove", remove_handler)
  g.post(ctx, "/sys/message/update", update_handler)
  g.post(ctx, "/sys/message/detail", detail_handler)
  g.post(ctx, "/sys/message/page", page_handler)
  g.post(ctx, "/sys/message/setRead", set_read_handler)
  g.post(ctx, "/sys/message/getUnreadCount", unread_handler)
  g.post(ctx, "/sys/message/getUnreadCountGroupByBizType", unread_group_handler)
}
