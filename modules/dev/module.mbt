// dev 模块自注册 —— 元数据只读面（gen/dev_schema 共用底座）；后续 dev_schema 台账进本模块

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] module(
  config : @core.MysqlConfig,
  g : @mbguard.Guard[S, P],
) -> @mb.Module {
  @mb.Module(ctx => {
    @ctrl.register(ctx, @metamysql.MetadataMysqlDao::make(config), g) catch {
      e => abort("dev 模块路由注册失败: \{e}")
    }
  })
}

///|
/// dev 模块权限策略聚合（main 并进总 policy）
pub fn policy() -> @guard.RoutePolicy {
  @ctrl.schema_policy()
}
