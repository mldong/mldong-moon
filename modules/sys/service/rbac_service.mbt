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
    Some(lid) =>
      // dao 的 MldongError 在 moon-token 端口边界转 Store（供数方故障语义）
      self.dao.find_perms_by_user(lid.user_id, lid.app_code) catch {
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
    Some(lid) =>
      self.dao.find_role_codes(lid.user_id, lid.app_code) catch {
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
    Some(lid) => {
      // 超管判定只看用户属性（admin_type），与 appCode 无关（boot2 同）
      let ua = self.dao.find_user_auth_by_id(lid.user_id) catch {
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
/// login_id 复合形态 "{user_id}@{app_code}"（appCode 是会话级属性：登录头定，
/// 缺省 platform；boot2 LoginUser.appCode 同语义——同用户不同 app 即独立会话族）。
/// provider 签名只有 login_id/device，appCode 编进 login_id 是不改 moon-token 的唯一干净路。
/// 缺 "@" 的旧形态按 platform 兼容。
struct LoginId {
  user_id : Int64
  app_code : String
}

///|
const DEFAULT_APP_CODE : String = "platform"

///|
fn parse_login_id(login_id : String) -> LoginId? {
  let parts = login_id.split("@").to_array()
  let id_part = parts[0].to_owned()
  let app = if parts.length() >= 2 {
    parts[1].to_owned()
  } else {
    DEFAULT_APP_CODE
  }
  if id_part.is_empty() {
    return None
  }
  try {
    Some({ user_id: @string.parse_int64(id_part), app_code: app })
  } catch {
    _ => None
  }
}
