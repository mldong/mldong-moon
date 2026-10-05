// sys_task_execution_history 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn taskexecutionhistory_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/taskExecutionHistory/save", ["sys:taskExecutionHistory:save"]))
    .rule(@guard.RouteRule::make("/sys/taskExecutionHistory/remove", ["sys:taskExecutionHistory:remove"]))
    .rule(@guard.RouteRule::make("/sys/taskExecutionHistory/update", ["sys:taskExecutionHistory:update"]))
    .rule(@guard.RouteRule::make("/sys/taskExecutionHistory/detail", ["sys:taskExecutionHistory:detail"]))
    .rule(@guard.RouteRule::make("/sys/taskExecutionHistory/page", ["sys:taskExecutionHistory:page"]))

    .rule(
      @guard.RouteRule::make("/sys/taskExecutionHistory/restore", ["sys:taskExecutionHistory:restore"]),
    )
  }

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.TaskExecutionHistoryService,
  Q : @dao.TaskExecutionQueueDao,
] register_taskexecutionhistory(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
  /// 队列表 dao（restore 重排队；module 接线，history 侧零构造）
  queue_dao : Q,
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.taskexecutionhistory_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.taskexecutionhistory_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    let ctx = @web.ctx_of(request)
    @core.ok_data(@dto.taskexecutionhistory_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.taskexecutionhistory_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.taskexecutionhistory_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/taskExecutionHistory/save", save_handler)
  g.post(ctx, "/sys/taskExecutionHistory/remove", remove_handler)
  g.post(ctx, "/sys/taskExecutionHistory/update", update_handler)
  g.post(ctx, "/sys/taskExecutionHistory/detail", detail_handler)
  g.post(ctx, "/sys/taskExecutionHistory/page", page_handler)
  // 恢复任务（boot2 TaskExecutionProvider.restoreTaskFromHistory 同语义）：历史行
  // 复制为新队列行（task_state=0 未开始、errorCount=0、variable 兜底 "{}"），历史行保留
  let restore_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let id = @core.get_i64(body, "id").unwrap_or(0L)
    if id == 0L {
      @core.fail(99999999, "id不能为空")
    } else {
      let h = svc.find_by_id(ctx, id)
      let new_allow = @core.get_int(body, "newAllowMaxErrorCount")
          let q : @entity.TaskExecutionQueue = {
            id: @core.next_id(),
            task_name: h.task_name,
            spring_bean_name: h.spring_bean_name,
            biz_id: h.biz_id,
            task_state: Some(0),
            latest_execution_time: None,
            allow_max_error_count: Some(match new_allow {
              Some(n) => n
              None => h.allow_max_error_count.unwrap_or(3)
            }),
            error_count: Some(0),
            error_reason: None,
            variable: Some(var_or_default(h.variable)),
            create_time: Some(@core.now_str()),
            create_user: h.create_user,
            update_time: Some(@core.now_str()),
            update_user: None,
          }
      let _ = queue_dao.insert(q)
      @core.ok_empty()
    }
  })
  g.post(ctx, "/sys/taskExecutionHistory/restore", restore_handler)
}
