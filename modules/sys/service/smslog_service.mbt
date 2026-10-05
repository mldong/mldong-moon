// sys_sms_log 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait SmsLogService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.SmsLogSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.SmsLogSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.SmsLog raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.SmsLogPageReq) -> (Int, Array[@entity.SmsLog]) raise @core.MldongError
}

///|
pub(all) struct SmsLogServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.SmsLogDao] SmsLogService for SmsLogServiceImpl[R] with fn save(self, _ctx, req) {
  let d : @entity.SmsLog = {
    id: @core.next_id(),
    task_id: req.task_id,
    phone: req.phone,
    biz_type: req.biz_type,
    provider: req.provider,
    content: req.content,
    status: req.status,
    error_msg: req.error_msg,
    cost_ms: req.cost_ms,
    client_ip: req.client_ip,
    create_time: Some(@core.now_str()),
    update_time: Some(@core.now_str()),
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.SmsLogDao] SmsLogService for SmsLogServiceImpl[R] with fn update(self, _ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.SmsLog = {
    id: req.id,
    task_id: req.task_id,
    phone: req.phone,
    biz_type: req.biz_type,
    provider: req.provider,
    content: req.content,
    status: req.status,
    error_msg: req.error_msg,
    cost_ms: req.cost_ms,
    client_ip: req.client_ip,
    create_time: None,
    update_time: Some(@core.now_str()),
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.SmsLogDao] SmsLogService for SmsLogServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.SmsLogDao] SmsLogService for SmsLogServiceImpl[R] with fn find_by_id(
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
pub impl[R : @dao.SmsLogDao] SmsLogService for SmsLogServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend SmsLogServiceImpl with SmsLogService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
