// sys_config 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn config_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/config/save", ["sys:config:save"]))
    .rule(@guard.RouteRule::make("/sys/config/remove", ["sys:config:remove"]))
    .rule(@guard.RouteRule::make("/sys/config/update", ["sys:config:update"]))
    .rule(@guard.RouteRule::make("/sys/config/detail", ["sys:config:detail"]))
    .rule(@guard.RouteRule::make("/sys/config/page", ["sys:config:page"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.ConfigService] register_config(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id = svc.save(@dto.config_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    svc.remove_by_ids(@core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    svc.update(@dto.config_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    @core.ok_data(@dto.config_json(svc.find_by_id(id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let req = @dto.config_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.config_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/config/save", save_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/config/remove", remove_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/config/update", update_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/config/detail", detail_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/config/page", page_handler) catch {
    e => raise e
  }
}
