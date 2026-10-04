// sys 模块自注册 —— 模块内装配（dao/service 构造 + 路由注册）收进模块，
// cmd/main 只挂模块不碰模块内部；新表加进本文件，新模块加到 main 一行。
//
// 模块签名收 config（显式传递，便于测试换库/env 统一读）；
// 返回 moonback Module（ctx.use_ 挂载，或直接在 root 闭包内调用）。

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] install(
  config : @core.MysqlConfig,
  g : @mbguard.Guard[S, P],
  auth : @app.TokenAuth[S, P],
  /// 框架级常量 holder（core 件，main 建实例传入）：sys 负责灌入/刷新，dev/biz 只读注入
  holder : @core.ConfigHolder,
) -> @mb.Module {
  @mb.Module(ctx => {
    let rbac_dao = @repo.RbacRepository::make(config)
    let rbac_svc = @svc.RbacServiceImpl::{ dao: rbac_dao }
    @ctrl.register_login(ctx, auth, rbac_svc, fn() { holder.get_bool("MOLE_CAPTCHA_OPEN", false) })
    // 常量 holder（boot2 ConstantContext 同位）：启动灌入，config 写路刷新；
    // 默认密码等系统参数从这读（env 优先），user service 经闭包注入不依赖 holder 类型
    let user_dao = @repo.UserRepository::make(config)
    let dept_dao = @repo.DeptRepository::make(config)
    let config_dao = @repo.ConfigRepository::make(config)
    // holder 由 main 建实例传入（本模块只灌入/刷新）
    holder.load_items(config_dao.list_all().map(fn(c) { (c.code, c.content) }))
    let user_svc = @svc.UserServiceImpl::{
      dao: user_dao,
      default_password_of: fn() { holder.get("M_DEFAULT_PASSWORD", @core.DEFAULT_PASSWORD) },
    }
    @ctrl.register(ctx, user_svc, rbac_svc, g, auth, async fn() raise @core.MldongError { dept_dao.list_all() }) catch {
      e => abort("sys 模块 user 路由注册失败: \{e}")
    }
    let role_dao = @repo.RoleRepository::make(config)
    let role_svc = @svc.RoleServiceImpl::{ dao: role_dao }
    @ctrl.register_role(ctx, role_svc, g) catch {
      e => abort("sys 模块 role 路由注册失败: \{e}")
    }
    // dept/post —— cmd/gen 生成（树端点直接长在生成文件里，二次开发即手改）
    let dept_svc = @svc.DeptServiceImpl::{ dao: dept_dao }
    @ctrl.register_dept(ctx, dept_svc, g) catch {
      e => abort("sys 模块 dept 路由注册失败: \{e}")
    }
    let post_dao = @repo.PostRepository::make(config)
    let post_svc = @svc.PostServiceImpl::{ dao: post_dao }
    @ctrl.register_post(ctx, post_svc, g) catch {
      e => abort("sys 模块 post 路由注册失败: \{e}")
    }
    // config —— cmd/gen 生成 + public/holder 二次开发（直接改生成物，扩展内容在文件内标注）
    let config_svc = @svc.ConfigServiceImpl::{ dao: config_dao, holder: Some(holder) }
    @ctrl.register_config(ctx, config_svc, g, async fn() raise @core.MldongError { config_dao.list_public() }) catch {
      e => abort("sys 模块 config 路由注册失败: \{e}")
    }
    // dict/dictItem —— cmd/gen 生成 + getByDictType/enumDictList/customDictList 二次开发
    // （枚举注册表静态声明、自定义注册中心存服务不存模型、请求时派生，UC-0431/0432）
    let dict_dao = @repo.DictRepository::make(config)
    let dict_item_dao = @repo.DictItemRepository::make(config)
    let dict_svc = @svc.DictServiceImpl::{
      dao: dict_dao,
      items_of: async fn(dict_id) raise @core.MldongError { dict_item_dao.list_enabled_by_dict(dict_id) },
      enum_models: @svc.enum_registry(),
      custom_providers: [],
    }
    @ctrl.register_dict(ctx, dict_svc, g) catch {
      e => abort("sys 模块 dict 路由注册失败: \{e}")
    }
    let dict_item_svc = @svc.DictItemServiceImpl::{
      dao: dict_item_dao,
      dict_exists: async fn(dict_id) raise @core.MldongError {
        match dict_dao.find_by_id(dict_id) {
          Some(_) => true
          None => false
        }
      },
    }
    @ctrl.register_dictitem(ctx, dict_item_svc, g) catch {
      e => abort("sys 模块 dictItem 路由注册失败: \{e}")
    }
  })
}

///|
/// RBAC 供数方构造（main 鉴权装配用：PermissionProvider 真实现，码链走库）
pub fn rbac_provider(config : @core.MysqlConfig) -> @svc.RbacServiceImpl[@repo.RbacRepository] {
  { dao: @repo.RbacRepository::make(config) }
}

///|
/// sys 模块权限策略聚合——各实体片段顺序折叠（新实体在数组里加一项即可）
pub fn policy() -> @guard.RoutePolicy {
  let fragments = [
    @ctrl.user_policy(),
    @ctrl.role_policy(),
    @ctrl.dept_policy(),
    @ctrl.post_policy(),
    @ctrl.config_policy(),
    @ctrl.dict_policy(),
    @ctrl.dictitem_policy(),
  ]
  let mut p = @guard.RoutePolicy::new()
  for f in fragments {
    p = @web.merge_policy(p, f)
  }
  p
}
