// sys_role 服务 —— 业务逻辑唯一收口（查重按 code，唯一索引语义）

///|
pub(open) trait RoleService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.RoleSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.RoleSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.Role raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.RolePageReq) -> (Int, Array[@entity.Role]) raise @core.MldongError
}

///|
pub(all) struct RoleServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.RoleDao] RoleService for RoleServiceImpl[R] with fn save(self, ctx, req) {
  // 业务规则：code 查重（未删除范围内；code 有唯一索引语义，空 code 不查）
  if !req.code.is_empty() {
    match self.dao.find_by_code(req.code) {
      Some(_) => raise @core.MldongError::InvalidParam("角色编码已存在: \{req.code}")
      None => ()
    }
  }
  let r : @entity.Role = {
    id: @core.next_id(),
    app_code: Some(ctx.resolve_app_code(req.app_code)),
    name: req.name,
    code: req.code,
    sort: req.sort,
    // 业务默认：自定义角色（role_type 列 NOT NULL，NULL 会插入失败；boot2 同款默认 1）
    role_type: Some(req.role_type.unwrap_or(1)),
    enabled: req.enabled,
    data_scope: req.data_scope,
    remark: req.remark,
    create_time: Some(@core.now_str()),
    update_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_user: ctx.user_id,
    is_deleted: Some(0),
  }
  self.dao.insert(r)
}

///|
pub impl[R : @dao.RoleDao] RoleService for RoleServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("角色不存在: \{req.id}")
    Some(_) => ()
  }
  if !req.code.is_empty() {
    match self.dao.find_by_code(req.code) {
      Some(other) => if other.id != req.id {
        raise @core.MldongError::InvalidParam("角色编码已存在: \{req.code}")
      }
      None => ()
    }
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖）
  let r : @entity.Role = {
    id: req.id,
    app_code: req.app_code,
    name: req.name,
    code: req.code,
    sort: req.sort,
    role_type: req.role_type,
    enabled: req.enabled,
    data_scope: req.data_scope,
    remark: req.remark,
    create_time: None,
    create_user: None,
    update_time: None,
    update_user: ctx.user_id,
    is_deleted: None,
  }
  self.dao.update(r)
}

///|
pub impl[R : @dao.RoleDao] RoleService for RoleServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.RoleDao] RoleService for RoleServiceImpl[R] with fn find_by_id(
  self,
  _ctx,
  id,
) {
  match self.dao.find_by_id(id) {
    Some(r) => r
    None => raise @core.MldongError::NotFound("角色不存在: \{id}")
  }
}

///|
pub impl[R : @dao.RoleDao] RoleService for RoleServiceImpl[R] with fn page(self, _ctx, req) {
  // 业务硬条件 + m_ 动态条件（role 单表无别名，m_ 键直接 3 段式）
  let w = @core.where_()
  let _ = w.eq("is_deleted", @core.I(0))
  let _ = w.append(req.m)
  // 关键字：缺省名称/编码双列
  let (kw, keys) = @core.parse_keywords_with_raw(
    req.keywords, req.search_keys,
    default_search_keys=["name", "code"],
  )
  if !kw.is_empty() && !keys.is_empty() {
    let ors : Array[String] = []
    let params : Array[@core.SqlValue] = []
    for c in keys {
      ors.push("\{c} like ?")
      params.push(@core.S("%\{kw}%"))
    }
    let _ = w.raw("(\{ors.join(" or ")})", params)
  }
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend RoleServiceImpl with RoleService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
