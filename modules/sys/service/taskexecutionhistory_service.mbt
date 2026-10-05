// sys_task_execution_history 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait TaskExecutionHistoryService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.TaskExecutionHistorySaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.TaskExecutionHistorySaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.TaskExecutionHistory raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.TaskExecutionHistoryPageReq) -> (Int, Array[@entity.TaskExecutionHistory]) raise @core.MldongError
}

///|
pub(all) struct TaskExecutionHistoryServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.TaskExecutionHistoryDao] TaskExecutionHistoryService for TaskExecutionHistoryServiceImpl[R] with fn save(self, ctx, req) {
  let d : @entity.TaskExecutionHistory = {
    id: @core.next_id(),
    task_name: req.task_name,
    spring_bean_name: req.spring_bean_name,
    biz_id: req.biz_id,
    task_state: req.task_state,
    finished_time: req.finished_time,
    allow_max_error_count: req.allow_max_error_count,
    error_count: req.error_count,
    error_reason: req.error_reason,
    variable: req.variable,
    create_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.TaskExecutionHistoryDao] TaskExecutionHistoryService for TaskExecutionHistoryServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.TaskExecutionHistory = {
    id: req.id,
    task_name: req.task_name,
    spring_bean_name: req.spring_bean_name,
    biz_id: req.biz_id,
    task_state: req.task_state,
    finished_time: req.finished_time,
    allow_max_error_count: req.allow_max_error_count,
    error_count: req.error_count,
    error_reason: req.error_reason,
    variable: req.variable,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.TaskExecutionHistoryDao] TaskExecutionHistoryService for TaskExecutionHistoryServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.TaskExecutionHistoryDao] TaskExecutionHistoryService for TaskExecutionHistoryServiceImpl[R] with fn find_by_id(
  self,
  _ctx,
  id,
) {
  match self.dao.find_by_id(id) {
    Some(d) => d
    None => raise @core.MldongError::NotFound("数据不存在: " + id.to_string())
  }
}

///|
pub impl[R : @dao.TaskExecutionHistoryDao] TaskExecutionHistoryService for TaskExecutionHistoryServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend TaskExecutionHistoryServiceImpl with TaskExecutionHistoryService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
