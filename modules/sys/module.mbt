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
  /// 框架级枚举字典注册中心（core 件，main 建实例传入）：各模块装配期灌自己的声明
  enum_registry : @core.EnumDictRegistry,
  /// 自定义字典供数方（装载器侧注入：插件经 PluginDictApi.expose 灌进来的活集合）
  custom_providers : Array[() -> Array[@core.DictModel]]
) -> @mb.Module {
  @mb.Module(ctx => {
    let rbac_dao = @repo.RbacRepository::make(config)
    let rbac_svc = @svc.RbacServiceImpl::{ dao: rbac_dao }
    @ctrl.register_login(ctx, auth, rbac_svc, fn() { holder.get_bool("MOLE_CAPTCHA_OPEN", false) })
    // 验证码 + SM2 公钥（公开面 ctx 直挂，豁免在 main 免名单；登录联动在 login_controller）
    @ctrl.register_captcha(ctx)
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
    // 枚举字典：本模块声明装配期灌注册中心（goframe init() 的 moon 同位）
    @enums.register_sys_enum_dicts(enum_registry)
    let dict_svc = @svc.DictServiceImpl::{
      dao: dict_dao,
      items_of: async fn(dict_id) raise @core.MldongError { dict_item_dao.list_enabled_by_dict(dict_id) },
      enums: enum_registry,
      custom_providers,
    }
    @ctrl.register_dict(ctx, dict_svc, g) catch {
      e => abort("sys 模块 dict 路由注册失败: \{e}")
    }
    // menu —— cmd/gen 生成 + tree/list/appList/userRouteMenu/syncRoute 二次开发
    // （RBAC 码链数据源的管理面；syncRoute 清理面靠闭包跨到 RbacRepository 级联 role_menu）
    let menu_dao = @repo.MenuRepository::make(config)
    let rbac_repo = @repo.RbacRepository::make(config)
    let menu_svc = @svc.MenuServiceImpl::{
      dao: menu_dao,
      app_list_of: async fn() raise @core.MldongError {
        dict_svc.get_by_dict_type(@core.Ctx::system(), "app_list")
      },
      menu_ids_of: async fn(user_id, app_code) raise @core.MldongError {
        rbac_repo.find_menu_ids_by_user(user_id, app_code)
      },
      perms_of: async fn(user_id, app_code) raise @core.MldongError {
        rbac_repo.find_perms_by_user(user_id, app_code)
      },
      purge_role_menus: async fn(menu_ids) raise @core.MldongError {
        rbac_repo.remove_role_menus_by_menu_ids(menu_ids)
      },
    }
    @ctrl.register_menu(ctx, menu_svc, g) catch {
      e => abort("sys 模块 menu 路由注册失败: \{e}")
    }
    // message —— cmd/gen 生成 + 接收人/appCode 隔离 + setRead/未读计数二次开发
    let message_repo = @repo.MessageRepository::make(config)
    let message_svc = @svc.MessageServiceImpl::{ dao: message_repo }
    @ctrl.register_message(ctx, message_svc, g) catch {
      e => abort("sys 模块 message 路由注册失败: \{e}")
    }
    // fileInfo —— cmd/gen 生成 + upload/getFileInfoByIds 二次开发（本地盘直写）
    // storage＝FileStorage 端口注入点：首版本地盘（LocalStorage），将来接 MinIO/S3
    // 只换这里的实现，sys_file_info 台账与四个分片端点都不动
    let fileinfo_svc = @svc.FileInfoServiceImpl::{
      dao: @repo.FileInfoRepository::make(config),
      storage: @svc.LocalStorage::make(@svc.upload_base_path()),
    }
    @ctrl.register_fileinfo(ctx, fileinfo_svc, g) catch {
      e => abort("sys 模块 fileInfo 路由注册失败: \{e}")
    }
    // lowcode —— 通用下拉 /{module}/{table}/select + /lowCode 动态表网关
    // （仅登录无权限码；controller 直用 GenericDao——纯基础设施无业务语义）
    @ctrl.register_lowcode(ctx, @repo.GenericDao::make(config), rbac_svc, g)
    // rbac —— 授权关系面（角色-菜单/用户-角色/数据范围，boot2 RbacController 同位）
    @ctrl.register_rbac(ctx, rbac_dao, g) catch {
      e => abort("sys 模块 rbac 路由注册失败: \{e}")
    }
    // 日志两表 + sms 两表 + 任务队列/历史（boot2 管理面 CRUD5，cmd/gen 生成 + 表配置按真实 schema 二开：
    // op_log/vis_log/sms_log/task_* 无 is_deleted 物理删，sms_log 无审计列）
    let oplog_svc = @svc.OpLogServiceImpl::{ dao: @repo.OpLogRepository::make(config) }
    @ctrl.register_oplog(ctx, oplog_svc, g) catch {
      e => abort("sys 模块 opLog 路由注册失败: \{e}")
    }
    let vislog_svc = @svc.VisLogServiceImpl::{ dao: @repo.VisLogRepository::make(config) }
    @ctrl.register_vislog(ctx, vislog_svc, g) catch {
      e => abort("sys 模块 visLog 路由注册失败: \{e}")
    }
    let smstemplate_svc = @svc.SmsTemplateServiceImpl::{ dao: @repo.SmsTemplateRepository::make(config) }
    @ctrl.register_smstemplate(ctx, smstemplate_svc, g) catch {
      e => abort("sys 模块 smsTemplate 路由注册失败: \{e}")
    }
    let smslog_svc = @svc.SmsLogServiceImpl::{ dao: @repo.SmsLogRepository::make(config) }
    @ctrl.register_smslog(ctx, smslog_svc, g) catch {
      e => abort("sys 模块 smsLog 路由注册失败: \{e}")
    }
    let taskhistory_dao = @repo.TaskExecutionHistoryRepository::make(config)
    let taskqueue_dao = @repo.TaskExecutionQueueRepository::make(config)
    let taskqueue_svc = @svc.TaskExecutionQueueServiceImpl::{ dao: taskqueue_dao }
    @ctrl.register_taskexecutionqueue(ctx, taskqueue_svc, g, taskhistory_dao) catch {
      e => abort("sys 模块 taskExecutionQueue 路由注册失败: \{e}")
    }
    let taskhistory_svc = @svc.TaskExecutionHistoryServiceImpl::{ dao: taskhistory_dao }
    @ctrl.register_taskexecutionhistory(ctx, taskhistory_svc, g, taskqueue_dao) catch {
      e => abort("sys 模块 taskExecutionHistory 路由注册失败: \{e}")
    }
    // sms 发送面（四端点：sendCode/verifyCode 公开 + sendNotification/batchSendNotification 权限码）
    @ctrl.register_sms(ctx, smslog_svc, smstemplate_svc.dao, g)
    // timer —— 内存态定时任务面（boot2 TimerCache 同位，无表）
    @ctrl.register_timer(ctx, g)
    // sse —— 站内信实时推送面（流式 + 心跳；仅登录无权限码，boot2 同位）
    @ctrl.register_sse(ctx, g)
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
    @ctrl.menu_policy(),
    @ctrl.message_policy(),
    @ctrl.fileinfo_policy(),
    @ctrl.rbac_policy(),
    @ctrl.oplog_policy(),
    @ctrl.vislog_policy(),
    @ctrl.smstemplate_policy(),
    @ctrl.smslog_policy(),
    @ctrl.sms_policy(),
    @ctrl.taskexecutionqueue_policy(),
    @ctrl.taskexecutionhistory_policy(),
    @ctrl.timer_policy(),
  ]
  let mut p = @guard.RoutePolicy::new()
  for f in fragments {
    p = @web.merge_policy(p, f)
  }
  p
}
