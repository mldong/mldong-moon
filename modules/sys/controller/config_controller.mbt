// sys_config 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn config_policy() -> @guard.RoutePolicy {
  // 二次开发：public 端点走豁免面（片段自带 exempt，module 聚合时 merge_policy 搬运）
  @guard.RoutePolicy::new()
    .exempt("/sys/config/public")
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
  /// 公开配置取数闭包（module 接线到 config dao，controller 零 dao 依赖）——二次开发
  list_public : async () -> Array[@entity.Config] raise @core.MldongError,
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.config_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.config_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    @core.ok_data(@dto.config_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.config_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.config_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/config/save", save_handler)
  g.post(ctx, "/sys/config/remove", remove_handler)
  g.post(ctx, "/sys/config/update", update_handler)
  g.post(ctx, "/sys/config/detail", detail_handler)
  g.post(ctx, "/sys/config/page", page_handler)
  // 公开配置（boot2 /sys/config/public @SaIgnore 同位）：PUBLIC 前缀且启用的 {code: content} map，
  // 登录页/版权等免登录读——豁免面路由（ctx.post 不经守卫，取数闭包由 module 接线）——二次开发
  let public_handler : @mb.Handler = @web.wrap(async fn(_request) -> Json raise @core.MldongError {
    let m : Map[String, Json] = Map([], capacity=0)
    for c in list_public() {
      let _ = m.set(c.code, Json::string(match c.content {
        Some(v) => v
        None => ""
      }))
    }
    @core.ok_data(Json::object(m))
  })
  ctx.post("/sys/config/public", public_handler)
}
