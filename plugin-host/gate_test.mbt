// 归属闸单测（零 DB）：六族语句形状 / 正反两档 / ScopedDb 纯逻辑（拼名冲突/越界/事务语句判据）。
// 需要真连接的行为（串行闸正负支 / exec_raw 审计落日志 / 请求边界）
// 走插件轮次 e2e——本文件只锁"闸的判据本身"。

///|
test "stmt_tables：六族语句形状 + IF EXISTS/IF NOT EXISTS + backtick" {
  assert_eq(
    @moon-plugin-host.stmt_tables("CREATE TABLE `p_portal_registration` (`id` bigint)"),
    ["p_portal_registration"],
  )
  assert_eq(
    @moon-plugin-host.stmt_tables("CREATE TABLE IF NOT EXISTS p_y (id int)"),
    ["p_y"],
  )
  assert_eq(
    @moon-plugin-host.stmt_tables("ALTER TABLE `sys_user` ADD COLUMN x int NULL"),
    ["sys_user"],
  )
  assert_eq(@moon-plugin-host.stmt_tables("DROP TABLE IF EXISTS p_old"), ["p_old"])
  assert_eq(
    @moon-plugin-host.stmt_tables("CREATE UNIQUE INDEX idx_x ON p_x (col)"),
    ["p_x"],
  )
  assert_eq(@moon-plugin-host.stmt_tables("DROP INDEX idx_x ON p_x"), ["p_x"])
  assert_eq(@moon-plugin-host.stmt_tables("TRUNCATE TABLE p_x"), ["p_x"])
  assert_eq(@moon-plugin-host.stmt_tables("TRUNCATE p_x"), ["p_x"])
}

///|
test "stmt_tables：ALTER 加列只认目标表，不把列名当表名" {
  assert_eq(
    @moon-plugin-host.stmt_tables("ALTER TABLE `p_portal_registration` ADD COLUMN `note` varchar(255) NULL"),
    ["p_portal_registration"],
  )
}

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
  migrations : Array[@moon-plugin-api.MigrationDecl],
) -> @moon-plugin-api.PluginDescriptor {
  {
    name,
    plugin_version: "1.0.0",
    spec_version: 1,
    requires: [],
    tables,
    migrations,
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
      [{ http_method: "POST", path: "/plugin/portal/register", perms: [], public: false }],
      [
        {
          version: 1,
          ddl: "CREATE TABLE `p_portal_registration` (`id` bigint NOT NULL, PRIMARY KEY (`id`))",
        },
      ],
    ),
    plugin_of("poster", ["reply"], [], []),
  ])
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_eq(err, "")
}

///|
test "归属闸负向：migration 动框架表 sys_user ⇒ 拒并点名" {
  let g = gate_of([
    plugin_of(
      "portal",
      ["registration"],
      [],
      [{ version: 1, ddl: "ALTER TABLE sys_user ADD COLUMN plugin_backdoor int NULL" }],
    ),
  ])
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("框架表"))
  assert_true(err.contains("sys_user"))
  assert_true(err.contains("portal"))
}

///|
test "归属闸（不变式）：同后缀不同插件=各自命名空间，合法" {
  // p_portal_registration 与 p_poster_registration 是两张表、各归其主——
  // 同后缀字面触发（两个插件同后缀）在 p_<name>_ 命名空间下不是碰撞；真碰撞是跨对拼名相撞
  let g = gate_of([
    plugin_of("portal", ["registration"], [], []),
    plugin_of("poster", ["registration"], [], []),
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
    plugin_of("portal", ["a_b"], [], []),
    plugin_of("portal_a", ["b"], [], []),
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
      [{ http_method: "POST", path: "/sys/user/page", perms: [], public: false }],
      [],
    ),
  ])
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("路由越界"))
}

///|
test "归属闸（收紧档）：migration 建了未声明的表 ⇒ 拒（卸载清表只认声明集）" {
  let g = gate_of([
    plugin_of(
      "portal",
      ["registration"],
      [],
      [{ version: 1, ddl: "CREATE TABLE `p_portal_extra` (`id` bigint NOT NULL)" }],
    ),
  ])
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("未在 tables 声明"))
}

///|
test "归属闸：插件名形状（大写/超短/保留名）" {
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
  let _ = @moon-plugin-host.validate_name("__framework__") catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("保留名"))
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
        [{ http_method: "POST", path: "/wf/processTask/todoList", perms: ["wf:processTask:todoList"], public: false }],
        [],
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
      plugin_of("jeeflow", [], [{ http_method: "POST", path: "/wf/a", perms: [], public: false }], []),
      plugin_of("other", [], [{ http_method: "POST", path: "/wf/b", perms: [], public: false }], []),
    ],
    contract_prefixes: ["/wf/"],
  }
  let mut err = ""
  let _ = g.validate() catch {
    e => err = @core.MldongError::message(e)
  }
  assert_true(err.contains("契约前缀冲突"))
}
