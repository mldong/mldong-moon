// sys 模块自注册 —— 模块内装配（dao/service 构造 + 路由注册）收进模块，
// cmd/main 只挂模块不碰模块内部；新表加进本文件，新模块加到 main 一行。
//
// 模块签名收 config（显式传递，便于测试换库/env 统一读）；
// 返回 moonback Module（ctx.use_ 挂载，或直接在 root 闭包内调用）。

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] module(
  config : @core.MysqlConfig,
  g : @mbguard.Guard[S, P],
  auth : @app.TokenAuth[S, P],
) -> @mb.Module {
  @mb.Module(ctx => {
    let rbac_dao = @mysql.RbacDaoMysql::make(config)
    let rbac_svc = @svc.RbacServiceImpl::{ dao: rbac_dao }
    @ctrl.register_login(ctx, auth, rbac_svc) catch {
      _ => abort("sys 模块登录路由注册失败（路由冲突?）")
    }
    let user_dao = @mysql.UserMysqlDao::make(config)
    let user_svc = @svc.UserServiceImpl::{ dao: user_dao }
    @ctrl.register(ctx, user_svc, rbac_svc, g, auth) catch {
      e => abort("sys 模块 user 路由注册失败: \{e}")
    }
    let role_dao = @mysql.RoleMysqlDao::make(config)
    let role_svc = @svc.RoleServiceImpl::{ dao: role_dao }
    @ctrl.register_role(ctx, role_svc, g) catch {
      e => abort("sys 模块 role 路由注册失败: \{e}")
    }
    // dept/post —— cmd/gen 生成（重生成可覆盖；树扩展在 dept_tree.mbt 手写面）
    let dept_dao = @mysql.DeptMysqlDao::make(config)
    let dept_svc = @svc.DeptServiceImpl::{ dao: dept_dao }
    @ctrl.register_dept(ctx, dept_svc, g) catch {
      e => abort("sys 模块 dept 路由注册失败: \{e}")
    }
    let post_dao = @mysql.PostMysqlDao::make(config)
    let post_svc = @svc.PostServiceImpl::{ dao: post_dao }
    @ctrl.register_post(ctx, post_svc, g) catch {
      e => abort("sys 模块 post 路由注册失败: \{e}")
    }
    // 树端点（取数闭包在此接线，controller 零 dao-mysql 依赖）
    let user_dao = @mysql.UserMysqlDao::make(config)
    @ctrl.register_dept_trees(ctx, async fn() raise @core.MldongError { dept_dao.list_all() }, async fn() raise @core.MldongError { user_dao.list_simple() }, g) catch {
      e => abort("sys 模块树路由注册失败: \{e}")
    }
    // config —— cmd/gen 生成 + public 二次开发（config_public.mbt 手写面）
    let config_dao = @mysql.ConfigMysqlDao::make(config)
    let config_svc = @svc.ConfigServiceImpl::{ dao: config_dao }
    @ctrl.register_config(ctx, config_svc, g) catch {
      e => abort("sys 模块 config 路由注册失败: \{e}")
    }
    @ctrl.register_config_public(ctx, async fn() raise @core.MldongError { config_dao.list_public() }) catch {
      e => abort("sys 模块 config 公开端点注册失败: \{e}")
    }
  })
}

///|
/// RBAC 供数方构造（main 鉴权装配用：PermissionProvider 真实现，码链走库）
pub fn rbac_provider(config : @core.MysqlConfig) -> @svc.RbacServiceImpl[@mysql.RbacDaoMysql] {
  { dao: @mysql.RbacDaoMysql::make(config) }
}

///|
/// sys 模块权限策略聚合——各实体片段合并（main 拿它并进总 policy）
pub fn policy() -> @guard.RoutePolicy {
  @web.merge_policy(
    @web.merge_policy(
      @web.merge_policy(@ctrl.user_policy(), @ctrl.role_policy()),
      @web.merge_policy(@ctrl.dept_policy(), @ctrl.post_policy()),
    ),
    @ctrl.dept_tree_policy(),
  ).exempt("/sys/config/public")
}
