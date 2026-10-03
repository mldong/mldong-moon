// RBAC 服务 —— 授权业务（中间表写路）+ moon-token 供数方（PermissionProvider 真实现，
// 替换骨架内存版：码的真实来源 = user_role → role_menu → menu.code，对齐 boot2 RbacService）

///|
pub(open) trait RbacService {
  /// 登录身份视图（userName 查用户；登录端点验存在/锁定用）
  async fn find_user_auth_by_name(Self, String) -> @entity.UserAuth? raise @core.MldongError
  /// 用户授权角色（user_role 全量替换）
  async fn grant_user_roles(Self, user_id : Int64, role_ids : Array[Int64]) -> Unit raise @core.MldongError
  /// 角色授权菜单（role_menu 全量替换）
  async fn grant_role_menus(Self, role_id : Int64, menu_ids : Array[Int64]) -> Unit raise @core.MldongError
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
/// 对齐 13 栈 sa-token StpUtil.login(user.getId())）
pub impl[D : @dao.RbacDao] @port.PermissionProvider for RbacServiceImpl[D] with fn get_permissions(
  self,
  login_id,
  _device,
) {
  match parse_login_id(login_id) {
    Some(id) =>
      // dao 的 MldongError 在 moon-token 端口边界转 Store（供数方故障语义）
      self.dao.find_perms_by_user(id) catch {
        e => raise @port.Store(e.message())
      }
    None => []
  }
}

///|
pub impl[D : @dao.RbacDao] @port.PermissionProvider for RbacServiceImpl[D] with fn get_roles(
  self,
  login_id,
  _device,
) {
  match parse_login_id(login_id) {
    Some(id) =>
      self.dao.find_role_codes(id) catch {
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
) {
  match parse_login_id(login_id) {
    Some(id) => {
      let ua = self.dao.find_user_auth_by_id(id) catch {
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
  grant_user_roles,
  grant_role_menus,
}

///|
/// login_id（user.id 的字符串形态）→ Int64；非数字视为无
fn parse_login_id(login_id : String) -> Int64? {
  if login_id.is_empty() {
    return None
  }
  try {
    Some(@string.parse_int64(login_id))
  } catch {
    _ => None
  }
}
