// jeeflow-moon 官方插件 —— 工作流引擎以插件身份进 mldong-moon（不走 base+1 集成壳）。
// 契约：全部 POST /wf/{action}，单 handler 全转发 Facade::flow（13 栈 JeeflowFacade 动态转发的
// moon 同位；action 含路径段，如 processTask/todoList）。
// 表归属：wf_* 8 张框架所有（已在基线脚本）——descriptor.tables 为空集，插件无 DDL。
// 引擎 schema 变更（wf_* 加列/改列）与 13 栈同法：改 java 侧编辑源 schema-mysql.sql →
// sync-schema.sh 逐字分发（含 jeeflow-moon 那份副本，门禁＝hub jeeflow-hub/scripts/
// check-doc-schema.py）→ 同步本仓 doc/sql/mysql-schema-all.sql 里的 wf_* 段。
// 装载器不带 schema 通道（10-09 owner 拍 C：与 13 栈库面重合），不再自动补建。
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
/// 权限码：`wf:{action，/→:}`（boot4 `WfFlowController.checkPermission` 同规律）——
/// 形如 `wf:processInstance:stats:overview`。**前缀必须有**：菜单种子里那 49 条 wf 按钮码全带 `wf:`
/// （现读 `sys_menu where code like 'wf:%'`），漏掉前缀会让非超管账号即使被授了权也恒 99990406
/// ——超管走 `is_super_admin` 豁免，所以这条只在真实授权账号上暴露，10-07 由 owner 前端走查抓出。
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
  "wf:" + sb.to_string()
}

///|
/// 登录即放行（不配权限码）的 action —— 引擎 `DefaultActionPermissionProvider.NO_PERM_ACTIONS`
/// 的 moon 同位（issues/29 归纳自 boot3「无 `@SaCheckPermission` 注解＝登录即可」）。
/// 统计那三条是 issues/103 的收口成果：分析页（概览→分析页）是人人可看的仪表盘，
/// 早先按默认规则拼出 `wf:processInstance:stats:*` 把普通用户整页拦死、toast 刷屏，
/// 六语言同款＝goframe `694d5b9` / fastapi `1aa5471` / salvo `58231b2` / nestjs `06e06c2` /
/// laravel `d39ebfc`；moon 这轮补齐（10-08 owner 前端走查抓出的正是同一条）。
let no_perm_actions : Array[String] = [
  "processInstance/detail",
  "processInstance/highLight",
  "processInstance/approvalRecord",
  "processInstance/getAssigneeTextData",
  "processInstance/bizData",
  "processTask/detail",
  "processTask/addCandidate",
  "processTask/latest",
  "processInstance/stats/overview",
  "processInstance/stats/trend",
  "processInstance/stats/group",
]

///|
/// 多码 OR（boot3 `@SaCheckPermission(value={...}, mode=OR)` 语义）：任一命中即有权。
/// 与引擎 `OR_RULES` 逐字对齐——漏一条就把"任一即可"做成"全都要"。
let or_rules : Array[(String, Array[String])] = [
  ("processDefine/detail", ["wf:processDefine:detail", "wf:processDesign:listByType"]),
  (
    "processDefine/startAndExecute",
    ["wf:processDefine:startAndExecute", "wf:processDesign:listByType"],
  ),
  (
    "processDefine/getLastByName",
    [
      "wf:processDefine:detail",
      "wf:processDesign:listByType",
      "wf:processDefine:getLastByName",
    ],
  ),
  ("processTask/candidatePage", ["wf:processTask:execute", "wf:processTask:candidatePage"]),
  ("processTask/jumpAbleTaskNameList", ["wf:processTask:execute"]),
]

///|
/// action → (权限码集合, 是否 OR)。空集合＝只验登录：`plugin_policy` 不给它挂 rule，
/// 主仓 `by_convention=false` 下未列端点即"仅登录"语义（与 boot3 无注解端点同形）。
pub fn perm_codes_of(action : String) -> (Array[String], Bool) {
  for a in no_perm_actions {
    if a == action {
      return ([], false)
    }
  }
  for (a, codes) in or_rules {
    if a == action {
      return (codes, true)
    }
  }
  ([perm_code(action)], false)
}

///|
/// descriptor —— 47 条 POST /wf/{action} 路由逐条显式权限码（主仓全显式语义不动）+ 一条
/// `/wf/*rest` 兜底（**仅登录、不配权限码**：它只回"未知 action"信封，不经引擎，故不给任何真实
/// 能力开门——13 栈的动态转发把未知 action 交给引擎答，moon 的显式面把"未声明即无此能力"看得更重，
/// 两种姿势的信封结论一致：code=99999999 且 msg 含「未知」）；
/// tables/migrations/menus 皆空集（见文件头）
pub fn jeeflow_descriptor() -> @api.PluginDescriptor {
  let routes : Array[@api.RouteDecl] = []
  for a in jeeflow_actions {
    let (codes, is_or) = perm_codes_of(a)
    routes.push({
      http_method: "POST",
      path: "/wf/\{a}",
      perms: codes,
      perm_or: is_or,
      public: false,
    })
  }
  // 兜底位必须排在 47 条静态位**之后**注册（moonback Trie：先静态前缀后通配，反了会抢命中）
  routes.push({
    http_method: "POST",
    path: "/wf/*rest",
    perms: [],
    perm_or: false,
    public: false,
  })
  {
    name: "jeeflow",
    plugin_version: "0.1.37", // 引擎代次（mooncakes mldong/jeeflow-*，随版更新；与 moon.mod 的四处 pin 同批抬）
    spec_version: @api.SPEC_VERSION, // 契约号定义单点在 plugin-api（此前这里硬编码同一个数、装载器侧再写一份 = 双写漂移）
    requires: [],
    tables: [],
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
