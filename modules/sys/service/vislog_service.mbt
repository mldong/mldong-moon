// sys_vis_log 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait VisLogService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.VisLogSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.VisLogSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.VisLog raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.VisLogPageReq) -> (Int, Array[@entity.VisLog]) raise @core.MldongError
}

///|
pub(all) struct VisLogServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.VisLogDao] VisLogService for VisLogServiceImpl[R] with fn save(self, _ctx, req) {
  let d : @entity.VisLog = {
    id: @core.next_id(),
    name: req.name,
    success: req.success,
    message: req.message,
    ip: req.ip,
    location: req.location,
    browser: req.browser,
    os: req.os,
    vis_type: req.vis_type,
    vis_time: req.vis_time,
    account: req.account,
    sign_value: req.sign_value,
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.VisLogDao] VisLogService for VisLogServiceImpl[R] with fn update(self, _ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.VisLog = {
    id: req.id,
    name: req.name,
    success: req.success,
    message: req.message,
    ip: req.ip,
    location: req.location,
    browser: req.browser,
    os: req.os,
    vis_type: req.vis_type,
    vis_time: req.vis_time,
    account: req.account,
    sign_value: req.sign_value,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.VisLogDao] VisLogService for VisLogServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.VisLogDao] VisLogService for VisLogServiceImpl[R] with fn find_by_id(
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
pub impl[R : @dao.VisLogDao] VisLogService for VisLogServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend VisLogServiceImpl with VisLogService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
