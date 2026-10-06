// jeeflow-moon 官方插件 —— 工作流引擎以插件身份进 mldong-moon（不走 base+1 集成壳）。
// 契约：全部 POST /wf/{action}，单 handler 全转发 Facade::flow（13 栈 JeeflowFacade 动态转发的
// moon 同位；action 含路径段，如 processTask/todoList）。
// 表归属：wf_* 8 张框架所有（已在基线脚本）——descriptor.tables 为空集，插件无 DDL；
// 引擎 schema 变更走 __framework__ 基线增量通道。
// 引擎装配：进程级一个 Facade，自带连接管理不经 ScopedDb（与 13 栈引擎自带连接池同构）。
// 用户供数 v1＝空实现（接口形状对齐 jeeflow demo；wf 链路里按人解析的节点返回缺省），
// operator 由 handler 直传 args（登录主体 login_id ＝ sys_user.id 字符串）；
// sys_user 真供数（IUserProvider 同位）＝下一刀。

///|
/// facade 的 action 名单（与引擎 dispatch 表逐字对齐；引擎新增 action ⇒ 本清单随版更新）
pub let jeeflow_actions : Array[String] = [
  "processDefine/page",
  "processDefine/detail",
  "processDefine/startAndExecute",
  "processDefine/deploy",
  "processDefine/redeploy",
  "processDefine/remove",
  "processDefine/upAndDown",
  "processDefine/getLastByName",
  "processInstance/page",
  "processInstance/detail",
  "processInstance/startAndExecute",
  "processInstance/withdraw",
  "processInstance/highLight",
  "processInstance/approvalRecord",
  "processInstance/getAssigneeTextData",
  "processInstance/bizData",
  "processInstance/createCCInstance",
  "processInstance/updateCCStatus",
  "processInstance/ccList",
  "processInstance/stats/overview",
  "processInstance/stats/trend",
  "processInstance/stats/group",
  "processTask/todoList",
  "processTask/doneList",
  "processTask/execute",
  "processTask/detail",
  "processTask/jumpAbleTaskNameList",
  "processTask/candidatePage",
  "processTask/surrogate",
  "processTask/addCandidate",
  "processTask/transfer",
  "processTask/removeTaskActor",
  "processTask/latest",
  "processDesign/page",
  "processDesign/detail",
  "processDesign/save",
  "processDesign/update",
  "processDesign/updateDefine",
  "processDesign/remove",
  "processDesign/deploy",
  "processDesign/redeploy",
  "processDesign/listByType",
  "processSurrogate/page",
  "processSurrogate/save",
  "processSurrogate/update",
  "processSurrogate/detail",
  "processSurrogate/remove",
]

///|
/// 权限码：wf:{action，/→:}（boot4 同规律）——wf:processInstance:stats:overview 形
pub fn perm_code(action : String) -> String {
  let sb = StringBuilder()
  for i in 0..<action.length() {
    match action.get_char(i) {
      Some(c) =>
        if c == '/' {
          sb.write_char(':')
        } else {
          sb.write_char(c)
        }
      None => ()
    }
  }
  sb.to_string()
}

///|
/// descriptor —— 47 条 POST /wf/{action} 路由逐条显式权限码（主仓全显式语义不动）；
/// tables/migrations/menus 皆空集（见文件头）
pub fn jeeflow_descriptor() -> @api.PluginDescriptor {
  let routes : Array[@api.RouteDecl] = []
  for a in jeeflow_actions {
    routes.push({
      http_method: "POST",
      path: "/wf/\{a}",
      perms: [perm_code(a)],
      public: false,
    })
  }
  {
    name: "jeeflow",
    plugin_version: "0.1.27", // 引擎代次（mooncakes mldong/jeeflow-*，随版更新）
    spec_version: 1, // 对齐 plugin-host 的 SPEC_VERSION（契约号，破坏性变更时同步 +1）
    requires: [],
    tables: [],
    migrations: [],
    routes,
    menus: [],
    dicts: [],
  }
}

///|
/// 用户供数 v1：空实现（demo 同形状空表）——按人解析的节点返回缺省；真供数＝下一刀
pub let find_user_v1 : (String) -> @model.UserInfo? raise @error.JeeflowError = uid => {
  let _ = uid
  None
}

///|
pub struct JeeflowPlugin {
  facade : @facade.Facade[@jrepo.MysqlRepository, @spi.NoExtRepository]
}

///|
/// 装配：MysqlRepository 桥接 @core.MysqlConfig（MLDONG_DB_* 同一库）→ Facade::make。
/// 引擎进程级一个实例；wasm 档已由 jeeflow-moon demo 实证。
pub fn JeeflowPlugin::make() -> JeeflowPlugin {
  let cfg = @core.MysqlConfig::from_env()
  let repo = @jrepo.MysqlRepository::make(@jrepo.MysqlConfig::{
    host: cfg.host,
    port: cfg.port,
    user: cfg.user,
    password: cfg.password,
    database: cfg.database,
  })
  let ctx = @spi.Ctx::new(repo, @spi.NoExtRepository::new())
  let gen = @id_gen.DefaultIdGenerator::new(2L)
  let ctx2 = ctx.with_id_generator(fn() { gen.next_id() })
  let ctx3 = ctx2.with_user_provider(find_user_v1)
  // org/search 供数 v1 同为空实现（形状对齐 demo；真供数下一刀）
  let ctx4 = ctx3.with_org_user_provider({
    find_dept_leaders: fn(_dept_id) { [] },
    find_dept_main_leaders: fn(_dept_id) { [] },
    find_by_role: fn(_role_code) { [] },
  })
  let _ = ctx4.with_user_search_provider({
    page: fn(query) { @model.PageResult::new(query.page_num(), query.page_size(), 0L, []) },
    find_by_id: fn(_uid) { None },
  })
  { facade: @facade.Facade::make(ctx4) }
}
