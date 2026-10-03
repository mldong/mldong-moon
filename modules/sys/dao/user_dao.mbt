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
  /// 条件分页：Wrapper 由 service 组装（业务说了算），返回 (总数, 当页行)
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.User]) raise @core.MldongError
}
