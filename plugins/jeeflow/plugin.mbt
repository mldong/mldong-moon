// jeeflow-moon 官方插件 —— 工作流引擎以插件身份进 mldong-moon（不走 base+1 集成壳）。
// 契约：全部 POST /wf/{action}，单 handler 全转发 Facade::flow（13 栈 JeeflowFacade 动态转发的
// moon 同位；action 含路径段，如 processTask/todoList）。
// 表归属：wf_* 8 张框架所有（已在基线脚本）——descriptor.tables 为空集，插件无 DDL；
// 引擎 schema 变更走 __framework__ 基线增量通道。
// 引擎装配：进程级一个 Facade，自带连接管理不经 ScopedDb（与 13 栈引擎自带连接池同构）；
// 装配动作在 initialize（供数预载需异步查库），make 只读定配置。
// 供数：引擎供数族 SPI 自 jeeflow-moon 0.1.28 起是 async 闭包（hub issues/146）⇒ initialize 里
// user/dept/role 快照，闭包读本地映射——新鲜度妥协的根因是引擎同步 SPI，v2 引擎 SPI
// 异步化后插件删快照直接 live 调端口。

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
    spec_version: 3, // 对齐 plugin-host 的 SPEC_VERSION（2→3：PluginContext 加 dicts 字典贡献面）
    requires: [],
    tables: [],
    migrations: [],
    routes,
    menus: [],
    dicts: [],
  }
}

///|
pub struct JeeflowPlugin {
  config : @core.MysqlConfig // 注册表期从 env 读定；引擎装配在 initialize（供数预载需异步查库）
}

///|
pub fn JeeflowPlugin::make() -> JeeflowPlugin {
  { config: @core.MysqlConfig::from_env() }
}
