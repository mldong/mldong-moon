// sys_role 仓储端口 —— 签名只用 entity/core 类型；单表查询，page 走 BaseDao 通用路径

///|
pub(open) trait RoleDao {
  async fn insert(Self, @entity.Role) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.Role) -> Unit raise @core.MldongError
  /// 逻辑删除（表配置驱动）
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.Role? raise @core.MldongError
  /// 编码查重（未删除范围内；code 有唯一索引语义）
  async fn find_by_code(Self, String) -> @entity.Role? raise @core.MldongError
  /// 条件分页（单表）：返回 (总数, 当页行)
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.Role]) raise @core.MldongError
}
