// sys_menu 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn menu_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/menu/save", ["sys:menu:save"]))
    .rule(@guard.RouteRule::make("/sys/menu/remove", ["sys:menu:remove"]))
    .rule(@guard.RouteRule::make("/sys/menu/update", ["sys:menu:update"]))
    .rule(@guard.RouteRule::make("/sys/menu/detail", ["sys:menu:detail"]))
    .rule(@guard.RouteRule::make("/sys/menu/page", ["sys:menu:page"]))
    // 二次开发（菜单树）：树/平铺列表
    .rule(@guard.RouteRule::make("/sys/menu/tree", ["sys:menu:tree"]))
    .rule(@guard.RouteRule::make("/sys/menu/list", ["sys:menu:list"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.MenuService] register_menu(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.menu_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.menu_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    let ctx = @web.ctx_of(request)
    @core.ok_data(@dto.menu_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.menu_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.menu_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/menu/save", save_handler)
  g.post(ctx, "/sys/menu/remove", remove_handler)
  g.post(ctx, "/sys/menu/update", update_handler)
  g.post(ctx, "/sys/menu/detail", detail_handler)
  // 菜单树（boot2 /sys/menu/tree 同位）：appCode 缺省登录上下文、sort 升序、children 嵌套
  let tree_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.menu_parse_page(@web.json_body(request))
    let nodes = svc.tree(ctx, req)
    let arr : Array[Json] = []
    for n in nodes {
      arr.push(menu_node_json(n))
    }
    @core.ok_data(Json::array(arr))
  })
  // 菜单平铺列表（boot2 /sys/menu/list 同位，orderBy 缺省 sort asc）
  let list_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.menu_parse_page(@web.json_body(request))
    let rows = svc.list(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.menu_json(row))
    }
    @core.ok_data(Json::array(arr))
  })
  g.post(ctx, "/sys/menu/page", page_handler)
  g.post(ctx, "/sys/menu/tree", tree_handler)
  g.post(ctx, "/sys/menu/list", list_handler)
}

///|
/// menu_json 套 children（动态键并回 Object——boot2 MenuVO + children 形状）
fn menu_node_json(n : @svc.MenuNode) -> Json {
  let base = match @dto.menu_json(n.menu) {
    Object(m) => m
    _ => Map([], capacity=0)
  }
  let arr : Array[Json] = []
  for c in n.children {
    arr.push(menu_node_json(c))
  }
  let _ = base.set("children", Json::array(arr))
  Json::object(base)
}
