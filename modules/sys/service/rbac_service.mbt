// RBAC 服务 —— 授权业务（中间表写路）+ moon-token 供数方（PermissionProvider 真实现，
// 替换骨架内存版：码的真实来源 = user_role → role_menu → menu.code，对齐 boot2 RbacService）

///|
pub(open) trait RbacService {
  /// 登录身份视图（userName 查用户；登录端点验存在/锁定用）
  async fn find_user_auth_by_name(Self, String) -> @entity.UserAuth? raise @core.MldongError
  /// 按 id 查登录身份视图（扮演端点：目标存在性/超管守卫 + 操作者账号回填）
  async fn find_user_auth_by_id(Self, Int64) -> @entity.UserAuth? raise @core.MldongError
  /// 用户授权角色（user_role 全量替换）
  async fn grant_user_roles(Self, user_id : Int64, role_ids : Array[Int64]) -> Unit raise @core.MldongError
  /// 角色授权菜单（role_menu 全量替换）
  async fn grant_role_menus(Self, role_id : Int64, menu_ids : Array[Int64]) -> Unit raise @core.MldongError
  /// 当前权限码（boot2 AuthServiceImpl.getPermissionList 同位）：超管**只出** `["admin"]`
  /// （CommonConstant.SUPER_ADMIN_PERM_FLAG，前端按它放行全部路由），其余按
  /// user_role→role_menu→menu.code 现取，appCode 取请求域。
  async fn perm_codes(Self, user_id : Int64, app_code : String) -> Array[String] raise @core.MldongError
}

///|
pub(all) struct RbacServiceImpl[D] {
  dao : D
}

///|
pub impl[D : @dao.RbacDao] RbacService for RbacServiceImpl[D] with fn find_user_auth_by_name(
  self,
  user_name,
) {
  self.dao.find_user_auth_by_name(user_name)
}

///|
pub impl[D : @dao.RbacDao] RbacService for RbacServiceImpl[D] with fn find_user_auth_by_id(
  self,
  user_id,
) {
  self.dao.find_user_auth_by_id(user_id)
}

///|
pub impl[D : @dao.RbacDao] RbacService for RbacServiceImpl[D] with fn grant_user_roles(
  self,
  user_id,
  role_ids,
) {
  match self.dao.find_user_auth_by_id(user_id) {
    None => raise @core.MldongError::NotFound("用户不存在: \{user_id}")
    Some(_) => ()
  }
  self.dao.grant_roles(user_id, role_ids)
}

///|
pub impl[D : @dao.RbacDao] RbacService for RbacServiceImpl[D] with fn grant_role_menus(
  self,
  role_id,
  menu_ids,
) {
  self.dao.grant_menus(role_id, menu_ids)
}

///|
/// moon-token 供数方：同一 struct 实现 PermissionProvider（login_id = sys_user.id 字符串，
/// 对齐 mldong 框架约定 boot2 登录 loginId 口径）。
/// extra = 登录时会话属性（appCode/ip/ua，登录端点塞入），appCode 从这取——
/// moon-token 0.1.9 起不再编进 login_id。
pub impl[D : @dao.RbacDao] @port.PermissionProvider for RbacServiceImpl[D] with fn get_permissions(
  self,
  login_id,
  _device,
  extra,
) {
  match parse_user_id(login_id) {
    Some(user_id) =>
      // dao 的 MldongError 在 moon-token 端口边界转 Store（供数方故障语义）
      self.dao.find_perms_by_user(user_id, app_code_of(extra)) catch {
        e => raise @port.Store(e.message())
      }
    None => []
  }
}

///|
pub impl[D : @dao.RbacDao] RbacService for RbacServiceImpl[D] with fn perm_codes(
  self,
  user_id,
  app_code,
) {
  match self.dao.find_user_auth_by_id(user_id) {
    Some(u) if u.admin_type == Some(1) => ["admin"]
    _ => self.dao.find_perms_by_user(user_id, app_code)
  }
}

///|
pub impl[D : @dao.RbacDao] @port.PermissionProvider for RbacServiceImpl[D] with fn get_roles(
  self,
  login_id,
  _device,
  extra,
) {
  match parse_user_id(login_id) {
    Some(user_id) =>
      self.dao.find_role_codes(user_id, app_code_of(extra)) catch {
        e => raise @port.Store(e.message())
      }
    None => []
  }
}

///|
pub impl[D : @dao.RbacDao] @port.PermissionProvider for RbacServiceImpl[D] with fn is_super_admin(
  self,
  login_id,
  _device,
  extra,
) {
  match parse_user_id(login_id) {
    Some(user_id) => {
      // 超管判定只看用户属性（admin_type），与 appCode 无关（boot2 同）
      let _ = extra
      let ua = self.dao.find_user_auth_by_id(user_id) catch {
        e => raise @port.Store(e.message())
      }
      match ua {
        Some(u) => u.admin_type == Some(1) // AdminTypeEnum.SUPER_ADMIN
        None => false
      }
    }
    None => false
  }
}

///|
pub extend RbacServiceImpl with RbacService::{
  find_user_auth_by_name,
  perm_codes,
  find_user_auth_by_id,
  grant_user_roles,
  grant_role_menus,
}

///|
pub extend RbacServiceImpl with @port.PermissionProvider::{
  get_permissions,
  get_roles,
  is_super_admin,
}

///|
/// login_id 就是 sys_user.id 字符串（appCode 走 extra，不再编进 login_id——
/// 免污染按 login_id 的搜索面；缺省 platform）。
/// 兼容形态：带 "@{appCode}" 的旧会话取 "@" 前段。
const DEFAULT_APP_CODE : String = "platform"

///|
pub fn parse_user_id(login_id : String) -> Int64? {
  @core.parse_user_id(login_id)
}

///|
/// extra 里取 appCode（登录端点塞的会话属性），缺省 platform
fn app_code_of(extra : Map[String, String]) -> String {
  match extra.get("appCode") {
    Some(v) => if v.is_empty() { DEFAULT_APP_CODE } else { v }
    None => DEFAULT_APP_CODE
  }
}
