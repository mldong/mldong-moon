// sys_dict_item 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait DictItemService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  /// save/update 先验父字典存在 + 字典内 code 唯一（boot2 DictItemServiceImpl 同位）
  async fn save(Self, @core.Ctx, @dto.DictItemSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.DictItemSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.DictItem raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.DictItemPageReq) -> (Int, Array[@entity.DictItem]) raise @core.MldongError
}

///|
pub(all) struct DictItemServiceImpl[R] {
  dao : R
  /// 父字典存在性（模块装配闭包注入，服务不依赖 DictDao 类型；boot2 dictMapper.selectById 同位）
  dict_exists : async (Int64) -> Bool raise @core.MldongError
}

///|
pub impl[R : @dao.DictItemDao] DictItemService for DictItemServiceImpl[R] with fn save(self, ctx, req) {
  // 父字典存在性（boot2 先查 dict 再落项；不存在报业务错而非静默）
  if !((self.dict_exists)(req.dict_id)) {
    raise @core.MldongError::InvalidInput("字典不存在: " + req.dict_id.to_string())
  }
  // 字典内编码唯一（boot2 checkUnique + custom eq(dict_id) 同位一行调）
  self.dao.check_unique_in_dict(req.dict_id, req.code, None, "唯一编码已存在: " + req.code)
  let d : @entity.DictItem = {
    id: @core.next_id(),
    dict_id: req.dict_id,
    name: req.name,
    code: req.code,
    sort: req.sort,
    enabled: req.enabled,
    remark: req.remark,
    variable: req.variable,
    create_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: Some(0),
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.DictItemDao] DictItemService for DictItemServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  if !((self.dict_exists)(req.dict_id)) {
    raise @core.MldongError::InvalidInput("字典不存在: " + req.dict_id.to_string())
  }
  // 字典内编码查重（排除自身）
  self.dao.check_unique_in_dict(req.dict_id, req.code, Some(req.id), "唯一编码已存在: " + req.code)
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.DictItem = {
    id: req.id,
    dict_id: req.dict_id,
    name: req.name,
    code: req.code,
    sort: req.sort,
    enabled: req.enabled,
    remark: req.remark,
    variable: req.variable,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: None,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.DictItemDao] DictItemService for DictItemServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.DictItemDao] DictItemService for DictItemServiceImpl[R] with fn find_by_id(
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
pub impl[R : @dao.DictItemDao] DictItemService for DictItemServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  // 关键字：searchKeys 列（snake 化 + 白名单过滤）OR 模糊；无 searchKeys 不应用（goframe 同语义）
  let (kw, keys) = @core.parse_keywords_with_raw(req.keywords, req.search_keys)
  if !kw.is_empty() && !keys.is_empty() {
    let ors : Array[String] = []
    let params : Array[@core.SqlValue] = []
    for c in keys {
      let col = @core.to_underscore(c)
      if @core.is_field_safe(col) {
        ors.push("\{col} like ?")
        params.push(@core.S("%\{kw}%"))
      }
    }
    if !ors.is_empty() {
      let _ = w.raw("(\{ors.join(" or ")})", params)
    }
  }
  // 排序：orderBy 白名单已过 parse_order_by；缺省 sort,id 升序（boot2 dictItem page orderByAsc(sort) 同款）
  let orders = if req.orders.is_empty() {
    [("sort", false), ("id", false)]
  } else {
    req.orders
  }
  self.dao.page(w, req.page_num, req.page_size, orders)
}

///|
pub extend DictItemServiceImpl with DictItemService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
