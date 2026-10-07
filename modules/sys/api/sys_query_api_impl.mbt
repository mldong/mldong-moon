// SysQueryApi 实现 —— api 层（provider 层，等同 boot4 mldong-sys-api 的 UserApi/DeptApiImpl）：
// 委托各域 service（业务收口，不在此写 SQL、不直接碰 repository），entity → 契约 DTO 的
// 转换也收在本层。契约在 plugin-api（依赖倒置：框架模块依赖契约包），cmd/main 注册插件时
// 注入 PluginContext；插件禁止依赖本模块。
// 字段面 = 用户/部门/岗位完整业务投影（不按单个消费方裁剪——后续业务同样需要这些信息）。

///|
pub struct SysQueryApiImpl {
  user_svc : @svc.UserServiceImpl[@repo.UserRepository]
  dept_svc : @svc.DeptServiceImpl[@repo.DeptRepository]
  post_svc : @svc.PostServiceImpl[@repo.PostRepository]
  rbac_dao : @repo.RbacRepository
}

///|
pub fn SysQueryApiImpl::make(
  config : @core.MysqlConfig,
) -> SysQueryApiImpl {
  {
    user_svc: @svc.UserServiceImpl::{ dao: @repo.UserRepository::make(config), default_password_of: fn() { @core.DEFAULT_PASSWORD } },
    dept_svc: @svc.DeptServiceImpl::{ dao: @repo.DeptRepository::make(config) },
    post_svc: @svc.PostServiceImpl::{ dao: @repo.PostRepository::make(config) },
    rbac_dao: @repo.RbacRepository::make(config),
  }
}

///|
/// ctx：查询面走系统上下文（插件调用无请求主体；审计落 NULL 与后台任务同惯例）
fn sys_ctx() -> @core.Ctx {
  @core.Ctx::system()
}

///|
fn user_detail_of(u : @entity.User, r : @entity.UserPageRow?) -> @api.SysUserDetail {
  let dept_id = u.dept_id
  let mut dept_name : String? = None
  let mut dept_code : String? = None
  let mut post_name : String? = None
  let mut post_code : String? = None
  match r {
    Some(row) => {
      dept_name = row.dept_name
      dept_code = row.dept_code
      post_name = row.post_name
      post_code = row.post_code
    }
    None => ()
  }
  {
    id: u.id,
    user_name: u.user_name,
    real_name: u.real_name,
    nick_name: u.nick_name,
    mobile_phone: u.mobile_phone,
    email: u.email,
    sex: u.sex,
    admin_type: u.admin_type,
    is_locked: u.is_locked,
    dept_id,
    dept_name,
    dept_code,
    post_id: u.post_id,
    post_name,
    post_code,
    remark: u.remark,
  }
}

///|
pub extend SysQueryApiImpl with @api.SysQueryApi::{user_by_id, user_page, user_list, dept_by_id, dept_list, post_list, role_user_pairs}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn user_by_id(
  self,
  id : Int64,
) -> @api.SysUserDetail? raise @core.MldongError {
  let ctx = sys_ctx()
  // service 语义 = 不存在 raise NotFound；查询面契约 = 返回 None（catch 里包 Some 统一两臂类型）
  let u_opt : Option[@entity.User] = Some(self.user_svc.find_by_id(ctx, id)) catch {
    @core.NotFound(_) => None
    e => raise @core.MldongError::Internal("user_by_id: \{@core.MldongError::message(e)}")
  }
  match u_opt {
    Some(u) => Some(user_detail_of(u, None))
    None => None
  }
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn user_page(
  self,
  q : @api.SysUserQuery,
) -> @api.SysUserPage raise @core.MldongError {
  let ctx = sys_ctx()
  let req : @dto.UserPageReq = {
    page_num: q.page,
    page_size: q.size,
    m: @core.where_(),
    keywords: q.keywords,
    search_keys: "userName,realName",
  }
  let (total, rows) = self.user_svc.page(ctx, req)
  let out : Array[@api.SysUserDetail] = []
  for row in rows {
    out.push(user_detail_of(row.user, Some(row)))
  }
  { rows: out, record_count: total }
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn user_list(
  self,
) -> Array[@api.SysUserDetail] raise @core.MldongError {
  let ctx = sys_ctx()
  let users = self.user_svc.list_simple(ctx)
  let out : Array[@api.SysUserDetail] = []
  for u in users {
    out.push(user_detail_of(u, None))
  }
  out
}

///|
/// leader_ids 逗号串拆数组（空串 → 空数组）
fn split_leader_ids(s : String) -> Array[String] {
  let ids : Array[String] = []
  for part in s.split(",") {
    let piece = part.trim().to_owned()
    if !piece.is_empty() {
      ids.push(piece)
    }
  }
  ids
}

///|
fn dept_detail_of(d : @entity.Dept) -> @api.SysDeptDetail {
  {
    id: d.id,
    name: d.name,
    code: d.code,
    parent_id: d.parent_id,
    leader_ids: split_leader_ids(d.leader_ids.unwrap_or("")),
    main_leader_id: d.main_leader_id,
    sort: d.sort,
  }
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn dept_by_id(
  self,
  id : Int64,
) -> @api.SysDeptDetail? raise @core.MldongError {
  let ctx = sys_ctx()
  let d_opt : Option[@entity.Dept] = Some(self.dept_svc.find_by_id(ctx, id)) catch {
    @core.NotFound(_) => None
    e => raise @core.MldongError::Internal("dept_by_id: \{@core.MldongError::message(e)}")
  }
  match d_opt {
    Some(d) => Some(dept_detail_of(d))
    None => None
  }
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn dept_list(
  self,
) -> Array[@api.SysDeptDetail] raise @core.MldongError {
  let ctx = sys_ctx()
  let depts = self.dept_svc.list_all(ctx)
  let out : Array[@api.SysDeptDetail] = []
  for d in depts {
    out.push(dept_detail_of(d))
  }
  out
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn post_list(
  self,
) -> Array[@api.SysPostDetail] raise @core.MldongError {
  let ctx = sys_ctx()
  let (_, posts) = self.post_svc.page(ctx, @dto.PostPageReq::{ page_num: 1, page_size: 500, m: @core.where_(), keywords: "", search_keys: "" })
  let out : Array[@api.SysPostDetail] = []
  for p in posts {
    out.push({ id: p.id, name: p.name, code: p.code, sort: p.sort })
  }
  out
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn role_user_pairs(
  self,
) -> Array[@api.SysRoleUser] raise @core.MldongError {
  let pairs = self.rbac_dao.role_user_pairs()
  let out : Array[@api.SysRoleUser] = []
  for p in pairs {
    out.push({ role_code: p.0, user_id: p.1.to_string() })
  }
  out
}
