// sys_sms_template 仓储端口 —— 签名只用 entity/core 类型（Wrapper 为 core 零 ORM 条件组）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(open) trait SmsTemplateDao {
  async fn insert(Self, @entity.SmsTemplate) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.SmsTemplate) -> Unit raise @core.MldongError
  /// 逻辑删除（表配置驱动）
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.SmsTemplate? raise @core.MldongError
  /// 批量按 id 查（remove 前收标识刷缓存等场景）
  async fn find_by_ids(Self, Array[Int64]) -> Array[@entity.SmsTemplate] raise @core.MldongError
  /// 分页：Wrapper 由 service 组装（业务说了算），返回 (总数, 当页行)
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.SmsTemplate]) raise @core.MldongError
  /// 模板唯一性（uk_biz_type_provider 语义前置：同 biz_type+provider 只一条）
  async fn check_unique(Self, Int, String, Int64?, String) -> Unit raise @core.MldongError
}
