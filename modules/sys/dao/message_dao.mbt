// sys_message 仓储端口 —— 签名只用 entity/core 类型（Wrapper 为 core 零 ORM 条件组）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(open) trait MessageDao {
  async fn insert(Self, @entity.Message) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.Message) -> Unit raise @core.MldongError
  /// 逻辑删除（表配置驱动）
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.Message? raise @core.MldongError
  /// 批量按 id 查（remove 前收标识刷缓存等场景）
  async fn find_by_ids(Self, Array[Int64]) -> Array[@entity.Message] raise @core.MldongError
  /// 分页：Wrapper 由 service 组装（业务说了算），返回 (总数, 当页行)
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.Message]) raise @core.MldongError
  /// 未读计数（接收人 + biz_type 前缀 LIKE；appCode 隔离）
  async fn count_unread(Self, Int64, String) -> Int raise @core.MldongError
  /// 未读按 biz_type 分组计数（boot2 countUnreadGroupByBizType 同序：biz_type asc）
  async fn count_unread_group(Self, Int64, String) -> Array[(String, Int)] raise @core.MldongError
  /// 置已读（仅本人消息 + biz_type 前缀域隔离；ids 空=本域全部已读，boot2 同语义）
  async fn set_read(Self, Int64, String, Array[Int64]) -> Unit raise @core.MldongError
  /// 逻辑删（仅本人消息 + 域隔离，boot2 LambdaUpdateWrapper receiver 同款）
  async fn remove_mine(Self, Int64, String, Array[Int64]) -> Unit raise @core.MldongError
}

