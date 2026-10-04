// sys_config 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait ConfigService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.ConfigSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.ConfigSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.Config raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.ConfigPageReq) -> (Int, Array[@entity.Config]) raise @core.MldongError
}

///|
pub(all) struct ConfigServiceImpl[R] {
  dao : R
  /// 常量刷新钩子（boot2 ConstantContext.putConstant 同位；None = 无 holder 直查库）。
  /// remove 先收 code 后逐个摘——boot2 靠定时任务自愈，骨架即时刷新
  mut holder : @core.ConfigHolder?
}

///|
pub impl[R : @dao.ConfigDao] ConfigService for ConfigServiceImpl[R] with fn save(self, ctx, req) {
  // 唯一编码校验（boot2 checkUnique 同位一行调）
  self.dao.check_unique(req.code, None, "唯一编码已存在: " + req.code)
  let d : @entity.Config = {
    id: @core.next_id(),
    name: req.name,
    code: req.code,
    group_code: req.group_code,
    content: req.content,
    is_sys: req.is_sys,
    enabled: req.enabled,
    remark: req.remark,
    create_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: Some(0),
  }
  match self.holder {
    Some(h) => h.put(req.code, req.content)
    None => ()
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.ConfigDao] ConfigService for ConfigServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 编码查重（排除自身）
  self.dao.check_unique(req.code, Some(req.id), "唯一编码已存在: " + req.code)
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.Config = {
    id: req.id,
    name: req.name,
    code: req.code,
    group_code: req.group_code,
    content: req.content,
    is_sys: req.is_sys,
    enabled: req.enabled,
    remark: req.remark,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: None,
  }
  match self.holder {
    Some(h) => h.put(req.code, req.content)
    None => ()
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.ConfigDao] ConfigService for ConfigServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  // 先收 code（删后查不到），删后逐个摘 holder——boot2 靠定时任务自愈，骨架即时刷新
  let items = self.dao.find_by_ids(ids)
  self.dao.remove_by_ids(ids)
  match self.holder {
    Some(h) =>
      for c in items {
        h.delete(c.code)
      }
    None => ()
  }
}

///|
pub impl[R : @dao.ConfigDao] ConfigService for ConfigServiceImpl[R] with fn find_by_id(
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
pub impl[R : @dao.ConfigDao] ConfigService for ConfigServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend ConfigServiceImpl with ConfigService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
