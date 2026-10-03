// sys_user 仓储端口 —— 签名只用 entity/core 类型（Wrapper 为 core 零 ORM 条件组），
// 零 moondb/moonmysql；业务怎么组合查询由 service 拼 Wrapper 传入

///|
pub(open) trait UserDao {
  async fn insert(Self, @entity.User) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.User) -> Unit raise @core.MldongError
  /// 逻辑删除（表配置驱动）
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.User? raise @core.MldongError
  /// 用户名查重（未删除范围内）
  async fn find_by_user_name(Self, String) -> @entity.User? raise @core.MldongError
  /// 关联分页（user + dept/post 名称）：Wrapper 由 service 组装（业务说了算），返回 (总数, 当页行)
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.UserPageRow]) raise @core.MldongError
  /// 批量按 id 查（在线列表 join 用户名/超管位用）
  async fn find_by_ids(Self, Array[Int64]) -> Array[@entity.User] raise @core.MldongError
  /// 锁定/解锁（is_locked 1/0，逻辑删范围外不碰）
  async fn set_locked(Self, Array[Int64], Int) -> Unit raise @core.MldongError
  /// 改密（service 算好散列+盐传入；updatePwd/resetPassword 共用）
  async fn update_password(Self, Int64, String, String) -> Unit raise @core.MldongError
  /// 下拉选项（userName/realName LIKE，上限 50，按创建时间倒序）
  async fn select_options(Self, String) -> Array[@entity.User] raise @core.MldongError
}
