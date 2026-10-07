// sys_sms_template 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait SmsTemplateService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.SmsTemplateSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.SmsTemplateSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.SmsTemplate raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.SmsTemplatePageReq) -> (Int, Array[@entity.SmsTemplate]) raise @core.MldongError
}

///|
pub(all) struct SmsTemplateServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.SmsTemplateDao] SmsTemplateService for SmsTemplateServiceImpl[R] with fn save(self, ctx, req) {
  // uk_biz_type_provider 唯一前置（DB 兜底 + 友好 99999999）
  self.dao.check_unique(req.biz_type, req.provider, None, "该业务类型下已存在同通道模板: " + req.biz_type.to_string())
  let d : @entity.SmsTemplate = {
    id: @core.next_id(),
    biz_type: req.biz_type,
    template_code: req.template_code,
    provider: req.provider,
    content: req.content,
    signature: req.signature,
    enabled: req.enabled,
    remark: req.remark,
    create_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: Some(0),
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.SmsTemplateDao] SmsTemplateService for SmsTemplateServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  self.dao.check_unique(req.biz_type, req.provider, Some(req.id), "该业务类型下已存在同通道模板: " + req.biz_type.to_string())
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.SmsTemplate = {
    id: req.id,
    biz_type: req.biz_type,
    template_code: req.template_code,
    provider: req.provider,
    content: req.content,
    signature: req.signature,
    enabled: req.enabled,
    remark: req.remark,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: None,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.SmsTemplateDao] SmsTemplateService for SmsTemplateServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.SmsTemplateDao] SmsTemplateService for SmsTemplateServiceImpl[R] with fn find_by_id(
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
pub impl[R : @dao.SmsTemplateDao] SmsTemplateService for SmsTemplateServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend SmsTemplateServiceImpl with SmsTemplateService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
