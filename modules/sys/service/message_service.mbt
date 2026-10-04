// sys_message 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait MessageService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.MessageSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.MessageSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.Message raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.MessagePageReq) -> (Int, Array[@entity.Message]) raise @core.MldongError
  /// 置已读（ids 空=全部已读；仅本人消息）
  async fn set_read(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  /// 未读计数（appCode biz_type 前缀隔离）
  async fn unread_count(Self, @core.Ctx) -> Int raise @core.MldongError
  /// 未读按 biz_type 分组（[{bizType,count}]，biz_type asc）
  async fn unread_count_group(Self, @core.Ctx) -> Array[Json] raise @core.MldongError
}

///|
/// appCode → biz_type 前缀 LIKE 模式（boot2 "appCode\_%" 转义下划线同款；
/// BS 看 PLATFORM_*、APP 看 APP_*——端隔离，双端互不可见）
pub fn biz_pat_of(app_code : String) -> String {
  let prefix = if app_code.is_empty() { "platform" } else { app_code }
  prefix + "\\_%"
}

///|
pub(all) struct MessageServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.MessageDao] MessageService for MessageServiceImpl[R] with fn save(self, ctx, req) {
  let d : @entity.Message = {
    id: @core.next_id(),
    title: req.title,
    content: req.content,
    msg_type: req.msg_type,
    biz_type: req.biz_type,
    biz_id: req.biz_id,
    receiver_user_id: req.receiver_user_id,
    sender_user_id: req.sender_user_id,
    sender_name: req.sender_name,
    url: req.url,
    variable: req.variable,
    is_read: req.is_read,
    create_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: Some(0),
  }
  // boot2 同位三件：发送人缺省=登录人、已读恒 0（DDL DEFAULT NULL 显式落 0）、
  // bizType 未带 appCode 前缀时自动补（与 page 过滤同一规则，否则本域消息本域不可见）
  if d.sender_user_id == 0L {
    d.sender_user_id = ctx.user_id.unwrap_or(0L)
  }
  d.is_read = Some(0)
  let app = ctx.app_code.unwrap_or("platform")
  if !app.is_empty() && !d.biz_type.has_prefix(app + "_") {
    d.biz_type = app + "_" + d.biz_type
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.MessageDao] MessageService for MessageServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.Message = {
    id: req.id,
    title: req.title,
    content: req.content,
    msg_type: req.msg_type,
    biz_type: req.biz_type,
    biz_id: req.biz_id,
    receiver_user_id: req.receiver_user_id,
    sender_user_id: req.sender_user_id,
    sender_name: req.sender_name,
    url: req.url,
    variable: req.variable,
    is_read: req.is_read,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: None,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.MessageDao] MessageService for MessageServiceImpl[R] with fn remove_by_ids(self, ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  // 仅本人消息可删（boot2 LambdaUpdateWrapper receiver 同款）
  self.dao.remove_mine(
    ctx.user_id.unwrap_or(0L),
    biz_pat_of(ctx.app_code.unwrap_or("platform")),
    ids,
  )
}

///|
pub impl[R : @dao.MessageDao] MessageService for MessageServiceImpl[R] with fn find_by_id(
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
pub impl[R : @dao.MessageDao] MessageService for MessageServiceImpl[R] with fn page(self, ctx, req) {
  // 接收人隔离（boot2 强制 receiver=当前用户）+ 端隔离（biz_type 前缀）先行，m_ 条件叠加
  let w = @core.where_()
  let _ = w.eq("receiver_user_id", @core.L(ctx.user_id.unwrap_or(0L)))
  let _ = w.like_pat("biz_type", biz_pat_of(ctx.app_code.unwrap_or("platform")))
  // bizTypes 过滤：自动补 appCode 前缀（boot2 同款；已带前缀的原样）
  let app = ctx.app_code.unwrap_or("platform")
  if req.biz_types.length() == 1 {
    let b = req.biz_types[0]
    let val = if b.has_prefix(app + "_") { b } else { app + "_" + b }
    let _ = w.eq("biz_type", @core.S(val))
  } else if req.biz_types.length() > 1 {
    let vals : Array[@core.SqlValue] = []
    for b in req.biz_types {
      vals.push(@core.S(if b.has_prefix(app + "_") { b } else { app + "_" + b }))
    }
    let _ = w.in_("biz_type", vals)
  }
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub impl[R : @dao.MessageDao] MessageService for MessageServiceImpl[R] with fn set_read(
  self,
  ctx,
  ids,
) {
  self.dao.set_read(
    ctx.user_id.unwrap_or(0L),
    biz_pat_of(ctx.app_code.unwrap_or("platform")),
    ids,
  )
}

///|
pub impl[R : @dao.MessageDao] MessageService for MessageServiceImpl[R] with fn unread_count(
  self,
  ctx,
) {
  self.dao.count_unread(ctx.user_id.unwrap_or(0L), biz_pat_of(ctx.app_code.unwrap_or("platform")))
}

///|
pub impl[R : @dao.MessageDao] MessageService for MessageServiceImpl[R] with fn unread_count_group(
  self,
  ctx,
) {
  let rows = self.dao.count_unread_group(
    ctx.user_id.unwrap_or(0L),
    biz_pat_of(ctx.app_code.unwrap_or("platform")),
  )
  let arr : Array[Json] = []
  for row in rows {
    arr.push({ "bizType": Json::string(row.0), "count": Json::number(row.1.to_double()) })
  }
  arr
}

///|
pub extend MessageServiceImpl with MessageService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
  set_read,
  unread_count,
  unread_count_group,
}
