// sys_role 控制器 —— 手写薄端点（同 user 形状）
// URL /sys/role/{save,remove,update,detail,page} 对齐 13 栈契约
// 权限码预留（guard 下一轮挂）：sys:role:save/remove/update/detail/page

///|
pub fn[T : @svc.RoleService] register_role(ctx : @mb.ModuleContext, svc : T) -> Unit raise {
  // 添加角色（code 查重在 service）
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id = svc.save(@dto.parse_role_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  // 删除角色
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    svc.remove_by_ids(@core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  // 修改角色
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    svc.update(@dto.parse_role_update(@web.json_body(request)))
    @core.ok_empty()
  })
  // 查询单个角色
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    @core.ok_data(@dto.role_json(svc.find_by_id(id)))
  })
  // 分页查询角色列表（单表 + m_ 动态条件）
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let req = @dto.parse_role_page(@web.json_body(request))
    let (total, rows) = svc.page(req)
    let arr : Array[Json] = []
    for r in rows {
      arr.push(@dto.role_json(r))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  ctx.post("/sys/role/save", save_handler) catch {
    e => raise e
  }
  ctx.post("/sys/role/remove", remove_handler) catch {
    e => raise e
  }
  ctx.post("/sys/role/update", update_handler) catch {
    e => raise e
  }
  ctx.post("/sys/role/detail", detail_handler) catch {
    e => raise e
  }
  ctx.post("/sys/role/page", page_handler) catch {
    e => raise e
  }
}
