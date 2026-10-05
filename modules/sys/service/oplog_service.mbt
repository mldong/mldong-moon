// sys_op_log 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait OpLogService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.OpLogSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.OpLogSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.OpLog raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.OpLogPageReq) -> (Int, Array[@entity.OpLog]) raise @core.MldongError
}

///|
pub(all) struct OpLogServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.OpLogDao] OpLogService for OpLogServiceImpl[R] with fn save(self, _ctx, req) {
  let d : @entity.OpLog = {
    id: @core.next_id(),
    name: req.name,
    op_type: req.op_type,
    success: req.success,
    message: req.message,
    ip: req.ip,
    location: req.location,
    browser: req.browser,
    os: req.os,
    url: req.url,
    class_name: req.class_name,
    method_name: req.method_name,
    req_method: req.req_method,
    param: req.param,
    result: req.result,
    op_time: req.op_time,
    account: req.account,
    play_user_account: req.play_user_account,
    request_no: req.request_no,
    sign_value: req.sign_value,
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.OpLogDao] OpLogService for OpLogServiceImpl[R] with fn update(self, _ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.OpLog = {
    id: req.id,
    name: req.name,
    op_type: req.op_type,
    success: req.success,
    message: req.message,
    ip: req.ip,
    location: req.location,
    browser: req.browser,
    os: req.os,
    url: req.url,
    class_name: req.class_name,
    method_name: req.method_name,
    req_method: req.req_method,
    param: req.param,
    result: req.result,
    op_time: req.op_time,
    account: req.account,
    play_user_account: req.play_user_account,
    request_no: req.request_no,
    sign_value: req.sign_value,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.OpLogDao] OpLogService for OpLogServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.OpLogDao] OpLogService for OpLogServiceImpl[R] with fn find_by_id(
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
pub impl[R : @dao.OpLogDao] OpLogService for OpLogServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend OpLogServiceImpl with OpLogService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
