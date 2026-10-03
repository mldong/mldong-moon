// sys 模块自注册 —— 模块内装配（dao/service 构造 + 路由注册）收进模块，
// cmd/main 只挂模块不碰模块内部；新表加进本文件，新模块加到 main 一行。
//
// 模块签名收 config（显式传递，便于测试换库/env 统一读）；
// 返回 moonback Module（ctx.use_ 挂载，或直接在 root 闭包内调用）。

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] module(config : @core.MysqlConfig, g : @mbguard.Guard[S, P]) -> @mb.Module {
  @mb.Module(ctx => {
    let user_dao = @mysql.UserMysqlDao::make(config)
    let user_svc = @svc.UserServiceImpl::{ dao: user_dao }
    @ctrl.register(ctx, user_svc, g) catch {
      e => abort("sys 模块 user 路由注册失败: \{e}")
    }
    let role_dao = @mysql.RoleMysqlDao::make(config)
    let role_svc = @svc.RoleServiceImpl::{ dao: role_dao }
    @ctrl.register_role(ctx, role_svc, g) catch {
      e => abort("sys 模块 role 路由注册失败: \{e}")
    }
  })
}

///|
/// sys 模块权限策略聚合——各实体片段合并（main 拿它并进总 policy）
pub fn policy() -> @guard.RoutePolicy {
  @web.merge_policy(@ctrl.user_policy(), @ctrl.role_policy())
}
