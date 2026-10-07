// /wf/{action} 权限码形状单测（零 DB）。
// 为什么单独钉这一条：菜单种子里 49 条 wf 按钮码全带 `wf:` 前缀，而超管走 is_super_admin 豁免——
// 前缀一旦漏掉，超管档全绿、被授权的普通账号恒 99990406，只有真实授权账号才暴露（10-07 前端走查抓到）。

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
test "perm_code：带 wf: 前缀且斜杠转冒号" {
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
test "descriptor：47 条路由逐条一条 wf: 权限码，且与路径同源" {
  let d = @moon-plugin-jeeflow.jeeflow_descriptor()
  assert_eq(d.routes.length(), 47)
  for r in d.routes {
    assert_eq(r.http_method, "POST")
    assert_eq(r.perms.length(), 1)
    let p = r.perms[0]
    assert_eq(p[0:3], "wf:")
    assert_eq(p, perm_of_path(r.path))
    assert_false(r.public)
  }
}
