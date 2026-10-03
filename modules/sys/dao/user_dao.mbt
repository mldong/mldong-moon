// sys_user 仓储端口 —— 签名只用 entity/dto，零 ORM 类型（moondb/moonmysql 只在 dao-mysql）

///|
pub(open) trait UserDao {
  async fn insert(Self, @entity.User) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.User) -> Unit raise @core.MldongError
  /// 逻辑删除（is_deleted=1）
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.User? raise @core.MldongError
  /// 用户名查重（未删除范围内）
  async fn find_by_user_name(Self, String) -> @entity.User? raise @core.MldongError
  /// 分页：返回 (总数, 当页行)
  async fn page(Self, @dto.UserPageReq) -> (Int, Array[@entity.User]) raise @core.MldongError
}
