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
  /// 授权写路：全量替换（删旧插新，repository 实现内局部事务）
  async fn grant_roles(Self, user_id : Int64, role_ids : Array[Int64]) -> Unit raise @core.MldongError
  async fn grant_menus(Self, role_id : Int64, menu_ids : Array[Int64]) -> Unit raise @core.MldongError
  /// 用户可见菜单 id 链（user_role → role_menu → menu.id；路由菜单非超管过滤用）——二次开发
  async fn find_menu_ids_by_user(Self, user_id : Int64, app_code : String) -> Array[Int64] raise @core.MldongError
  /// role_menu 按菜单 id 清理（syncRoute 删菜单时级联）——二次开发
  async fn remove_role_menus_by_menu_ids(Self, menu_ids : Array[Int64]) -> Unit raise @core.MldongError
  /// 角色 → 菜单 id 清单（roleMenuIds 回显）
  async fn find_menu_ids_by_role(Self, role_id : Int64) -> Array[Int64] raise @core.MldongError
  /// 用户-角色增量授权（saveUserRole 逐对插，不动存量）
  async fn grant_user_role_pairs(Self, pairs : Array[(Int64, Int64)]) -> Unit raise @core.MldongError
  /// 用户-角色移除（removeUserRole 逐对删）
  async fn remove_user_role_pairs(Self, pairs : Array[(Int64, Int64)]) -> Unit raise @core.MldongError
  /// 角色下用户分页（userListByRoleId=true / userListExcludeRoleId=false）
  async fn page_users_by_role(
    Self,
    role_id : Int64,
    in_role : Bool,
    w : @core.Wrapper,
    page_num : Int,
    page_size : Int,
  ) -> (Int, Array[@entity.User]) raise @core.MldongError
  /// 数据范围授权（sys_role_dept 全量替换 + sys_role.data_scope 直更）
  async fn grant_data_scope(Self, role_id : Int64, data_scope : Int?, dept_ids : Array[Int64]) -> Unit raise @core.MldongError
}
