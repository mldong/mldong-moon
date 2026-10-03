// sys_user 控制器 —— 手写薄端点（boot2 风格：校验在 dto、业务在 service、响应工具在 core）
// URL /sys/user/{save,remove,update,detail,page} 对齐 13 栈契约
// 权限码预留（guard 下一轮挂）：save=sys:user:save remove=sys:user:remove
// update=sys:user:update detail=sys:user:detail page=sys:user:page

///|
pub fn[T : @svc.UserService] register(ctx : @mb.ModuleContext, svc : T) -> Unit raise {
  // 添加用户
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id = svc.save(@dto.parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  // 删除用户（逻辑删，ids 支持字符串/数字）
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    svc.remove_by_ids(@core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  // 修改用户
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    svc.update(@dto.parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  // 查询单个用户
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    @core.ok_data(@dto.user_json(svc.find_by_id(id)))
  })
  // 分页查询用户列表（关联 dept/post + m_ 动态条件）
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let req = @dto.parse_page(@web.json_body(request))
    let (total, rows) = svc.page(req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.page_row_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  ctx.post("/sys/user/save", save_handler) catch {
    e => raise e
  }
  ctx.post("/sys/user/remove", remove_handler) catch {
    e => raise e
  }
  ctx.post("/sys/user/update", update_handler) catch {
    e => raise e
  }
  ctx.post("/sys/user/detail", detail_handler) catch {
    e => raise e
  }
  ctx.post("/sys/user/page", page_handler) catch {
    e => raise e
  }
}
