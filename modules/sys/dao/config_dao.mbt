// sys_config 仓储端口 —— 签名只用 entity/core 类型（Wrapper 为 core 零 ORM 条件组）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(open) trait ConfigDao {
  async fn insert(Self, @entity.Config) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.Config) -> Unit raise @core.MldongError
  /// 逻辑删除（表配置驱动）
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.Config? raise @core.MldongError
  /// 编码查重（未删除范围内）
  async fn find_by_code(Self, String) -> @entity.Config? raise @core.MldongError
  /// 分页：Wrapper 由 service 组装（业务说了算），返回 (总数, 当页行)
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.Config]) raise @core.MldongError
}
