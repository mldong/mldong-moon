// 归属闸 + 在册对账单测（零 DB）：正反两档 / ScopedDb 纯逻辑（拼名冲突/越界/事务语句判据）。
// 需要真连接的行为（串行闸正负支 / exec_raw 审计落日志 / 请求边界）
// 走插件轮次 e2e——本文件只锁"闸的判据本身"。
// 10-09 拍 C 之后本包不再有 migration 应用器，故 stmt_tables 与"migration 越界"两族判据随之撤销。

///|
fn gate_of(plugins : Array[@moon-plugin-api.PluginDescriptor]) -> @moon-plugin-host.OwnershipGate {
  { framework_tables: [
      "sys_user", "sys_dict", "sys_menu", "wf_process_define", "dev_schema", "biz_demo",
    ], plugins, contract_prefixes: [] }
}

///|
fn plugin_of(
  name : String,
  tables : Array[String],
  routes : Array[@moon-plugin-api.RouteDecl],
) -> @moon-plugin-api.PluginDescriptor {
  {
    name,
    plugin_version: "1.0.0",
    spec_version: @moon-plugin-api.SPEC_VERSION,
    requires: [],
    tables,
    routes,
    menus: [],
    dicts: [],
  }
}

///|
test "归属闸正向：合规插件过闸不被误伤（正向对照）" {
  let g = gate_of([
    plugin_of(
      "portal",
      ["registration"],
      [{ http_method: "POST", path: "/plugin/portal/register", perms: [], perm_or: false, public: false }],
    ),
    plugin_of("poster", ["reply"], []),
  ])
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_eq(err, "")
}

///|
test "归属闸负向：声明后缀撞出框架基线表名 ⇒ 拒并点名（p_ 面被占的防线）" {
  // 注入坏样本证判据敢报红：framework_tables 里放一张 p_portal_registration
  // （现实里框架基线不带 p_，这道闸防的是"手工把插件表写进基线脚本又被 own 档重复声明"）
  let g : @moon-plugin-host.OwnershipGate = {
    framework_tables: ["p_portal_registration", "sys_user"],
    plugins: [plugin_of("portal", ["registration"], [])],
    contract_prefixes: [],
  }
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("撞框架基线表"))
  assert_true(err.contains("p_portal_registration"))
}

///|
test "归属闸（不变式）：同后缀不同插件=各自命名空间，合法" {
  // p_portal_registration 与 p_poster_registration 是两张表、各归其主——
  // 同后缀字面触发（两个插件同后缀）在 p_<name>_ 命名空间下不是碰撞；真碰撞是跨对拼名相撞
  let g = gate_of([
    plugin_of("portal", ["registration"], []),
    plugin_of("poster", ["registration"], []),
  ])
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_eq(err, "")
}

///|
test "归属闸：跨对拼名相撞（portal+a_b ≡ portal_a+b）⇒ 拒装并点名冲突表与两个所有者" {
  let g = gate_of([
    plugin_of("portal", ["a_b"], []),
    plugin_of("portal_a", ["b"], []),
  ])
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("p_portal_a_b"))
  assert_true(err.contains("portal"))
  assert_true(err.contains("portal_a"))
}

///|
test "归属闸：路由不以 /plugin/<name>/ 开头 ⇒ 拒" {
  let g = gate_of([
    plugin_of(
      "portal",
      ["registration"],
      [{ http_method: "POST", path: "/sys/user/page", perms: [], perm_or: false, public: false }],
    ),
  ])
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("路由越界"))
}

///|
test "归属闸：插件名形状（大写/超短/旧保留名下划线开头）" {
  let mut err = ""
  let _ = @moon-plugin-host.validate_name("Portal") catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("形状不合法"))
  err = ""
  let _ = @moon-plugin-host.validate_name("a") catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("长度"))
  err = ""
  // 旧保留组名 __framework__ 现读无专门保留名规则，靠形状（首字符须小写字母）排掉
  let _ = @moon-plugin-host.validate_name("__framework__") catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("形状不合法"))
}

///|
test "在册对账正向：声明表齐 ⇒ 过（含 tables 为空集的插件）" {
  let db : Map[String, Bool] = Map([], capacity=4)
  db["p_portal_registration"] = true
  db["sys_user"] = true
  let mut err = ""
  let _ = @moon-plugin-host.reconcile_registered(
    [plugin_of("portal", ["registration"], []), plugin_of("jeeflow", [], [])],
    db,
  ) catch {
    e => err = @core.MldongError::message(e)
  }
  assert_eq(err, "")
}

///|
test "在册对账负向：声明了但库里缺 ⇒ 拒并点名缺哪张（装载器不补建）" {
  let db : Map[String, Bool] = Map([], capacity=2)
  db["sys_user"] = true
  let mut err = ""
  let _ = @moon-plugin-host.reconcile_registered(
    [plugin_of("portal", ["registration", "reply"], [])],
    db,
  ) catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("p_portal_registration"))
  assert_true(err.contains("p_portal_reply"))
}

///|
test "在册对账负向：库里有 p_ghost_* 而注册表无 ghost ⇒ 残留，拒" {
  let db : Map[String, Bool] = Map([], capacity=2)
  db["p_ghost_orphan"] = true
  db["sys_user"] = true
  let mut err = ""
  let _ = @moon-plugin-host.reconcile_registered(
    [plugin_of("portal", [], [])],
    db,
  ) catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("ghost"))
  assert_true(err.contains("p_ghost_orphan"))
}

///|
test "ScopedDb：后缀走声明的拼名，未声明/框架名都拒且点名所有者" {
  assert_eq(
    @moon-plugin-host.resolve_table("portal", ["registration"], "registration"),
    "p_portal_registration",
  )
  let mut err = ""
  let _ : String = @moon-plugin-host.resolve_table("portal", ["registration"], "sys_user") catch {
    e => {
      err = @core.MldongError::message(e)
      ""
    }
  }
  assert_true(err.contains("sys_user"))
  assert_true(err.contains("portal"))
}

///|
test "ScopedDb：事务语句首词判据（大小写不敏感）" {
  assert_true(@moon-plugin-host.is_transaction_word("begin"))
  assert_true(@moon-plugin-host.is_transaction_word("COMMIT"))
  assert_true(@moon-plugin-host.is_transaction_word("Rollback"))
  assert_true(@moon-plugin-host.is_transaction_word("START"))
  assert_true(!@moon-plugin-host.is_transaction_word("select"))
  assert_true(!@moon-plugin-host.is_transaction_word("insert"))
}

///|
test "归属闸：契约前缀白名单放行官方契约路由（jeeflow /wf/ 形状）" {
  let g : @moon-plugin-host.OwnershipGate = {
    framework_tables: ["sys_user", "wf_process_define"],
    plugins: [
      plugin_of(
        "jeeflow",
        [],
        [{ http_method: "POST", path: "/wf/processTask/todoList", perms: ["wf:processTask:todoList"], perm_or: false, public: false }],
      ),
    ],
    contract_prefixes: ["/wf/"],
  }
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_eq(err, "")
}

///|
test "归属闸：契约前缀两两不撞（两插件同用 /wf/ 即拒）" {
  let g : @moon-plugin-host.OwnershipGate = {
    framework_tables: [],
    plugins: [
      plugin_of("jeeflow", [], [{ http_method: "POST", path: "/wf/a", perms: [], perm_or: false, public: false }]),
      plugin_of("other", [], [{ http_method: "POST", path: "/wf/b", perms: [], perm_or: false, public: false }]),
    ],
    contract_prefixes: ["/wf/"],
  }
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("契约前缀冲突"))
}
