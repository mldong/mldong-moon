// /wf/{action} 权限码形状单测（零 DB）。
// 为什么单独钉这一条：菜单种子里 49 条 wf 按钮码全带 `wf:` 前缀，而超管走 is_super_admin 豁免——
// 前缀写错、放行清单漏一条，超管档全绿照样藏着，只有真实授权账号才暴露
// （10-07 抓前缀、10-08 抓 stats 三条放行清单，两次都是 owner 在前端点出来的）。

fn perm_of_path(path : String) -> String {
  // "/wf/processInstance/page" → "wf:processInstance:page"
  let tail = path[4:]
  let sb = StringBuilder()
  for i in 0..<tail.length() {
    match tail.get_char(i) {
      Some('/') => sb.write_char(':')
      Some(c) => sb.write_char(c)
      None => ()
    }
  }
  "wf:" + sb.to_string()
}

///|
test "perm_code：默认规则带 wf: 前缀且斜杠转冒号" {
  assert_eq(
    @moon-plugin-jeeflow.perm_code("processTask/todoList"),
    "wf:processTask:todoList",
  )
  assert_eq(
    @moon-plugin-jeeflow.perm_code("processInstance/stats/overview"),
    "wf:processInstance:stats:overview",
  )
  assert_eq(
    @moon-plugin-jeeflow.perm_code("processInstance/page"),
    "wf:processInstance:page",
  )
}

///|
test "perm_codes_of：统计三条与详情族登录即放行（引擎 NO_PERM_ACTIONS 同位）" {
  // 分析页（概览→分析页）人人可看：这三条一旦按默认规则拼码，普通用户整页被拦成 toast 刷屏
  for a in [
    "processInstance/stats/overview",
    "processInstance/stats/trend",
    "processInstance/stats/group",
    // 其余八条同属"boot3 无注解＝登录即可"族
    "processInstance/detail",
    "processInstance/highLight",
    "processInstance/approvalRecord",
    "processInstance/getAssigneeTextData",
    "processInstance/bizData",
    "processTask/detail",
    "processTask/addCandidate",
    "processTask/latest",
  ] {
    let (codes, is_or) = @moon-plugin-jeeflow.perm_codes_of(a)
    assert_eq(codes, [], msg=a + " 应为空码＝只验登录")
    assert_false(is_or)
  }
}

///|
test "perm_codes_of：OR 族逐条与引擎 OR_RULES 对齐" {
  let (d1, o1) = @moon-plugin-jeeflow.perm_codes_of("processDefine/detail")
  assert_true(o1)
  assert_eq(d1, ["wf:processDefine:detail", "wf:processDesign:listByType"])
  let (d2, o2) = @moon-plugin-jeeflow.perm_codes_of("processDefine/getLastByName")
  assert_true(o2)
  assert_eq(
    d2,
    [
      "wf:processDefine:detail",
      "wf:processDesign:listByType",
      "wf:processDefine:getLastByName",
    ],
  )
  let (d3, o3) = @moon-plugin-jeeflow.perm_codes_of("processTask/jumpAbleTaskNameList")
  assert_true(o3)
  assert_eq(d3, ["wf:processTask:execute"])
  let (d4, o4) = @moon-plugin-jeeflow.perm_codes_of("processTask/candidatePage")
  assert_true(o4)
  assert_eq(d4, ["wf:processTask:execute", "wf:processTask:candidatePage"])
  let (d5, o5) = @moon-plugin-jeeflow.perm_codes_of("processDefine/startAndExecute")
  assert_true(o5)
  assert_eq(d5, ["wf:processDefine:startAndExecute", "wf:processDesign:listByType"])
}

///|
test "descriptor：47 条 action 路由逐条与路径同源 + 1 条未知 action 兜底位，且放行/OR/默认三族分类不串" {
  let d = @moon-plugin-jeeflow.jeeflow_descriptor()
  // 兜底位是清单外的一条（它不对应任何引擎 action，只回「未知」信封），故总数 = action 数 + 1；
  // 三族计数只在下面对**前 47 条 action 位**统计，兜底位单独钉形状，防止它被配出权限码或被 public 放行。
  assert_eq(d.routes.length(), 48)
  let mut login_only = 0
  let mut or_routes = 0
  let mut default_routes = 0
  for r in d.routes[:47] {
    assert_eq(r.http_method, "POST")
    assert_false(r.public)
    if r.perms.is_empty() {
      login_only += 1
    } else if r.perm_or {
      or_routes += 1
      for p in r.perms {
        assert_eq(p[0:3], "wf:")
      }
    } else {
      default_routes += 1
      // 默认族恰好一条码，且等于"路径去 /wf/ 后斜杠转冒号再拼 wf:"
      assert_eq(r.perms.length(), 1)
      assert_eq(r.perms[0], perm_of_path(r.path))
    }
  }
  // 三族数量与引擎那张表逐一对上：47 条里放行 11、OR 5、默认 31
  assert_eq(login_only, 11)
  assert_eq(or_routes, 5)
  assert_eq(default_routes, 31)
  // 兜底位（第 48 条）单独钉形状：不配权限码、不放行、路径就是 /wf/*rest——
  // 它一旦被配上权限码或标成 public，就等于给清单外的 action 开了一条带鉴权语义的可达面
  let tail = d.routes[47]
  assert_eq(tail.path, "/wf/*rest")
  assert_true(tail.perms.is_empty())
  assert_false(tail.public)
}
