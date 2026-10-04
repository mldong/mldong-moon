// sys_dict 仓储端口 —— 签名只用 entity/core 类型（Wrapper 为 core 零 ORM 条件组）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(open) trait DictDao {
  async fn insert(Self, @entity.Dict) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.Dict) -> Unit raise @core.MldongError
  /// 逻辑删除（表配置驱动）
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.Dict? raise @core.MldongError
  /// 批量按 id 查（remove 前收标识刷缓存等场景）
  async fn find_by_ids(Self, Array[Int64]) -> Array[@entity.Dict] raise @core.MldongError
  /// 唯一编码校验（boot2 checkUnique 同位一行调：存在且排除自身即 Conflict）
  async fn check_unique(Self, String, Int64?, String) -> Unit raise @core.MldongError
  /// 分页：Wrapper 由 service 组装（业务说了算），返回 (总数, 当页行)
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.Dict]) raise @core.MldongError
  /// 按编码取启用字典（getByDictType 首选源；boot2 code+enabled 同位）——二次开发
  async fn find_enabled_by_code(Self, String) -> @entity.Dict? raise @core.MldongError
}
