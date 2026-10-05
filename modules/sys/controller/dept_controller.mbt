// sys_dept 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn dept_policy() -> @guard.RoutePolicy {
  let tree_rule = @guard.RouteRule::make("/sys/dept/tree", ["sys:dept:tree", "sys:role:grantDataScope"])
  tree_rule.perm_mode = @port.Or
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/dept/save", ["sys:dept:save"]))
    .rule(@guard.RouteRule::make("/sys/dept/remove", ["sys:dept:remove"]))
    .rule(@guard.RouteRule::make("/sys/dept/update", ["sys:dept:update"]))
    .rule(@guard.RouteRule::make("/sys/dept/detail", ["sys:dept:detail"]))
    .rule(@guard.RouteRule::make("/sys/dept/page", ["sys:dept:page"]))
    // 二次开发（树表）：部门树端点
    .rule(@guard.RouteRule::make("/sys/dept/list", ["sys:dept:list"]))
    // 部门树（boot2 双码 OR：授权数据范围弹窗借道部门树）
    .rule(tree_rule)
    .rule(@guard.RouteRule::make("/sys/dept/autoSort", ["sys:dept:autoSort"]))
    .rule(@guard.RouteRule::make("/sys/dept/updateSort", ["sys:dept:updateSort"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.DeptService] register_dept(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.dept_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.dept_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    @core.ok_data(@dto.dept_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.dept_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.dept_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/dept/save", save_handler)
  g.post(ctx, "/sys/dept/remove", remove_handler)
  g.post(ctx, "/sys/dept/update", update_handler)
  g.post(ctx, "/sys/dept/detail", detail_handler)
  g.post(ctx, "/sys/dept/page", page_handler)
  // 部门树（boot2 /sys/dept/list：全量平表 → parent_id 建树）——二次开发（树表）
  let list_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let tree = @svc.build_dept_tree(svc.list_all(ctx))
    let arr : Array[Json] = []
    for n in tree {
      arr.push(dept_node_json(n))
    }
    @core.ok_data(Json::array(arr))
  })
  // 部门树（boot2 /sys/dept/tree 同位：与 list 同数据源，双码 OR 供授权弹窗借道）
  let tree_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let tree = @svc.build_dept_tree(svc.list_all(ctx))
    let arr : Array[Json] = []
    for n in tree {
      arr.push(dept_node_json(n))
    }
    @core.ok_data(Json::array(arr))
  })
  // 自动排序（boot2 autoSort：sort = 层级×10000 + 层内序×1000）
  let auto_sort_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.auto_sort(ctx)
    @core.ok_empty()
  })
  // 批量拖拽排序（boot2 updateSort：[{id,sort}] 直更）
  let update_sort_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let items : Array[(Int64, Int64)] = []
    match @web.json_body(request) {
      Array(rows) =>
        for row in rows {
          let id = @core.get_i64(row, "id").unwrap_or(0L)
          let sort = @core.get_i64(row, "sort").unwrap_or(0L)
          if id != 0L {
            items.push((id, sort))
          }
        }
      _ => ()
    }
    svc.update_sort(ctx, items)
    @core.ok_empty()
  })
  g.post(ctx, "/sys/dept/list", list_handler)
  g.post(ctx, "/sys/dept/tree", tree_handler)
  g.post(ctx, "/sys/dept/autoSort", auto_sort_handler)
  g.post(ctx, "/sys/dept/updateSort", update_sort_handler)
}

///|
/// dept_json 套 children（动态键并回 Object——boot2 DeptVO + children 形状）
fn dept_node_json(n : @svc.DeptNode) -> Json {
  let base = match @dto.dept_json(n.dept) {
    Object(m) => m
    _ => Map([], capacity=0)
  }
  let arr : Array[Json] = []
  for c in n.children {
    arr.push(dept_node_json(c))
  }
  let _ = base.set("children", Json::array(arr))
  Json::object(base)
}
