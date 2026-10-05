// sys_task_execution_queue 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn taskexecutionqueue_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/taskExecutionQueue/save", ["sys:taskExecutionQueue:save"]))
    .rule(@guard.RouteRule::make("/sys/taskExecutionQueue/remove", ["sys:taskExecutionQueue:remove"]))
    .rule(@guard.RouteRule::make("/sys/taskExecutionQueue/update", ["sys:taskExecutionQueue:update"]))
    .rule(@guard.RouteRule::make("/sys/taskExecutionQueue/detail", ["sys:taskExecutionQueue:detail"]))
    .rule(@guard.RouteRule::make("/sys/taskExecutionQueue/page", ["sys:taskExecutionQueue:page"]))
    .rule(
      @guard.RouteRule::make("/sys/taskExecutionQueue/cancelTask", ["sys:taskExecutionQueue:cancelTask"]),
    )
}

///|
/// variable 兜底（boot2 同：空/缺 → "{}"）
fn var_or_default(v : String?) -> String {
  match v {
    Some(s) => if s.is_empty() { "{}" } else { s }
    None => "{}"
  }
}

///|
pub fn[
  S : @port.TokenStore,
  P : @port.PermissionProvider,
  T : @svc.TaskExecutionQueueService,
  H : @dao.TaskExecutionHistoryDao,
] register_taskexecutionqueue(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
  /// 历史表 dao（cancelTask 转历史落行；module 接线，queue 侧零构造）
  history_dao : H,
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.taskexecutionqueue_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.taskexecutionqueue_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    let ctx = @web.ctx_of(request)
    @core.ok_data(@dto.taskexecutionqueue_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.taskexecutionqueue_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.taskexecutionqueue_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/taskExecutionQueue/save", save_handler)
  g.post(ctx, "/sys/taskExecutionQueue/remove", remove_handler)
  g.post(ctx, "/sys/taskExecutionQueue/update", update_handler)
  g.post(ctx, "/sys/taskExecutionQueue/detail", detail_handler)
  g.post(ctx, "/sys/taskExecutionQueue/page", page_handler)
  // 取消任务（boot2 TaskExecutionProvider.cancelTask 同语义）：队列行转历史
  // （同 id、task_state=3 已取消、finishedTime=now、errorReason=cancelReason）后删队列行
  let cancel_task_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let id = @core.get_i64(body, "id").unwrap_or(0L)
    if id == 0L {
      @core.fail(99999999, "id不能为空")
    } else {
      let q = svc.find_by_id(ctx, id)
      {
        let h : @entity.TaskExecutionHistory = {
            id: q.id,
            task_name: q.task_name,
            spring_bean_name: q.spring_bean_name,
            biz_id: q.biz_id,
            task_state: Some(3),
            finished_time: Some(@core.now_str()),
            allow_max_error_count: q.allow_max_error_count,
            error_count: q.error_count,
            error_reason: @core.get_text(body, "cancelReason"),
            variable: Some(var_or_default(q.variable)),
            create_time: q.create_time,
            create_user: q.create_user,
            update_time: Some(@core.now_str()),
            update_user: None,
          }
        let _ = history_dao.insert(h)
        svc.remove_by_ids(ctx, [id])
        @core.ok_empty()
      }
    }
  })
  g.post(ctx, "/sys/taskExecutionQueue/cancelTask", cancel_task_handler)
}
