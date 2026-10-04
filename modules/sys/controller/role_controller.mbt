// sys_role 控制器 —— 手写薄端点（同 user 形状）
// URL /sys/role/{save,remove,update,detail,page} 对齐 mldong 接口契约
// 权限码预留（guard 下一轮挂）：sys:role:save/remove/update/detail/page

///|
/// 权限码片段（role 五端点；位置与维护规则同 user_policy）
pub fn role_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/role/save", ["sys:role:save"]))
    .rule(@guard.RouteRule::make("/sys/role/remove", ["sys:role:remove"]))
    .rule(@guard.RouteRule::make("/sys/role/update", ["sys:role:update"]))
    .rule(@guard.RouteRule::make("/sys/role/detail", ["sys:role:detail"]))
    .rule(@guard.RouteRule::make("/sys/role/page", ["sys:role:page"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.RoleService] register_role(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  // 添加角色（code 查重在 service）
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.parse_role_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  // 删除角色
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  // 修改角色
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.parse_role_update(@web.json_body(request)))
    @core.ok_empty()
  })
  // 查询单个角色
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    @core.ok_data(@dto.role_json(svc.find_by_id(ctx, id)))
  })
  // 分页查询角色列表（单表 + m_ 动态条件）
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.parse_role_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for r in rows {
      arr.push(@dto.role_json(r))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/role/save", save_handler)
  g.post(ctx, "/sys/role/remove", remove_handler)
  g.post(ctx, "/sys/role/update", update_handler)
  g.post(ctx, "/sys/role/detail", detail_handler)
  g.post(ctx, "/sys/role/page", page_handler)
}
