// dev_schema 仓储端口 —— 签名只用 entity/core 类型（Wrapper 为 core 零 ORM 条件组）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(open) trait SchemaDao {
  async fn insert(Self, @entity.Schema) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.Schema) -> Unit raise @core.MldongError
  /// 逻辑删除（表配置驱动）
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.Schema? raise @core.MldongError
  /// 批量按 id 查（remove 前收标识刷缓存等场景）
  async fn find_by_ids(Self, Array[Int64]) -> Array[@entity.Schema] raise @core.MldongError
  /// 分页：Wrapper 由 service 组装（业务说了算），返回 (总数, 当页行)
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.Schema]) raise @core.MldongError
  /// 按表名查（importTable 历史检测 + getByTableName 名称解析）
  async fn find_by_table_name(Self, String) -> @entity.Schema? raise @core.MldongError
  /// 分组内模型清单（schemaGroup 聚合 schemaList；sort 升序）
  async fn list_by_group_id(Self, Int64) -> Array[@entity.Schema] raise @core.MldongError
  /// 已导入表名清单（dbTable disabled 标记；is_deleted=0）
  async fn list_imported_names(Self) -> Array[String] raise @core.MldongError
  /// 列表/搜索键直更（col 白名单在仓储层钉死：list_keys/search_form_keys）
  async fn update_keys(Self, Int64, String, String) -> Unit raise @core.MldongError
}

