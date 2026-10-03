// RBAC 仓储端口 —— 权限链查询（provider 供数）+ 两张中间表（sys_user_role/sys_role_menu）的
// 授权写路。中间表不立六件套（mldong 框架同构：boot2 的 UserRole/RoleMenu 只有 MP 实体无独立
// controller/service，授权挂在主表 service，全量替换式写入）——查询归 provider 链、写归主表。

///|
pub(open) trait RbacDao {
  /// 登录身份视图（userName → id/admin_type/is_locked）
  async fn find_user_auth_by_name(Self, String) -> @entity.UserAuth? raise @core.MldongError
  async fn find_user_auth_by_id(Self, Int64) -> @entity.UserAuth? raise @core.MldongError
  /// 用户角色编码（user_role ⋈ role.code，按 role.app_code 过滤）
  async fn find_role_codes(Self, user_id : Int64, app_code : String) -> Array[String] raise @core.MldongError
  /// 权限码链：user_role ⋈ role_menu ⋈ menu.code（去重，按 role/menu 的 app_code 过滤）
  async fn find_perms_by_user(Self, user_id : Int64, app_code : String) -> Array[String] raise @core.MldongError
  /// 授权写路：全量替换（删旧插新，dao-mysql 实现内局部事务）
  async fn grant_roles(Self, user_id : Int64, role_ids : Array[Int64]) -> Unit raise @core.MldongError
  async fn grant_menus(Self, role_id : Int64, menu_ids : Array[Int64]) -> Unit raise @core.MldongError
}
