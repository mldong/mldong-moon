// dev 模块自注册 —— 元数据只读面（gen 底座）+ dev_schema 台账三件套（boot2 dev 对齐）

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] install(
  config : @core.MysqlConfig,
  g : @mbguard.Guard[S, P],
  holder : @core.ConfigHolder,
  enum_registry : @core.EnumDictRegistry,
  auth : @app.TokenAuth[S, P],
) -> @mb.Module {
  @mb.Module(ctx => {
    // dev 域 4 枚举字典（与 sys 同一条注册中心传链）
    @enums.register_dev_enum_dicts(enum_registry)
    let meta_dao = @metamysql.MetadataMysqlDao::make(config)
    @ctrl.register_metadata(ctx, meta_dao, g) catch {
      e => abort("dev 元数据路由注册失败: \{e}")
    }
    let schema_repo = @repo.SchemaRepository::make(config)
    let field_repo = @repo.SchemaFieldRepository::make(config)
    let group_repo = @repo.SchemaGroupRepository::make(config)
    let schema_svc = @svc.SchemaServiceImpl::{
      dao: schema_repo,
      fields: field_repo,
      groups: group_repo,
      meta: meta_dao,
      holder,
    }
    let field_svc = @svc.SchemaFieldServiceImpl::{ dao: field_repo }
    let group_svc = @svc.SchemaGroupServiceImpl::{ dao: group_repo }
    @ctrl.register_schema(ctx, schema_svc, g, holder, auth) catch {
      e => abort("dev schema 路由注册失败: \{e}")
    }
    @ctrl.register_schemafield(ctx, field_svc, g) catch {
      e => abort("dev schemaField 路由注册失败: \{e}")
    }
    @ctrl.register_schemagroup(ctx, group_svc, g) catch {
      e => abort("dev schemaGroup 路由注册失败: \{e}")
    }
  })
}

///|
/// dev 模块权限策略聚合（main 并进总 policy）
pub fn policy() -> @guard.RoutePolicy {
  let a = @web.merge_policy(@ctrl.schema_policy(), @ctrl.schemafield_policy())
  let b = @web.merge_policy(@ctrl.schemagroup_policy(), @ctrl.metadata_policy())
  @web.merge_policy(a, b)
}
