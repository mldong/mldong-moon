// dev_schema_field 仓储端口 —— 签名只用 entity/core 类型（Wrapper 为 core 零 ORM 条件组）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(open) trait SchemaFieldDao {
  async fn insert(Self, @entity.SchemaField) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.SchemaField) -> Unit raise @core.MldongError
  /// 逻辑删除（表配置驱动）
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.SchemaField? raise @core.MldongError
  /// 批量按 id 查（remove 前收标识刷缓存等场景）
  async fn find_by_ids(Self, Array[Int64]) -> Array[@entity.SchemaField] raise @core.MldongError
  /// 分页：Wrapper 由 service 组装（业务说了算），返回 (总数, 当页行)
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.SchemaField]) raise @core.MldongError
  /// 模型字段清单（detail/getByTableName columns；sort,id 升序）
  async fn list_by_schema_id(Self, Int64) -> Array[@entity.SchemaField] raise @core.MldongError
  /// 物理删该模型的全部字段（importTable 历史 + updateDesigner 全删重插；boot2 @TableLogic 注释同语义）
  async fn delete_by_schema_id(Self, Int64) -> Unit raise @core.MldongError
  /// 物理删（字段行 remove 走硬删，boot2 同语义）
  async fn delete_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  /// 全删重插一个事务收口（updateDesigner；boot2 @Transactional 同语义）
  async fn replace_schema_fields(Self, Int64, Array[@entity.SchemaField]) -> Unit raise @core.MldongError
  /// 单行 sort 直更（updateSort 拖拽算法落点）
  async fn update_sort_value(Self, Int64, Int64) -> Unit raise @core.MldongError
}

