// descriptor 验收：Array[&Plugin] 能装两个异构实现并遍历 descriptor()
//（trait 方法首参显式 self ⇒ 异构实现可进 trait object 数组，隐式 upcast）
// 注：_test.mbt 里引用本包类型须用 @moon-plugin-api. 限定（test_unqualified_package 门禁）

///|
struct AlphaPlugin {
  version : String
}

///|
impl @moon-plugin-api.Plugin for AlphaPlugin with fn descriptor(
  self : AlphaPlugin,
) -> @moon-plugin-api.PluginDescriptor {
  {
    name: "alpha",
    plugin_version: self.version,
    spec_version: 1,
    requires: [],
    tables: ["registration"],
    migrations: [],
    routes: [],
    menus: [],
    dicts: [],
  }
}

///|
impl @moon-plugin-api.Plugin for AlphaPlugin with fn initialize(
  self : AlphaPlugin,
  ctx : @moon-plugin-api.PluginContext,
) -> Unit raise {
  let _ = self
  let _ = ctx
}

///|
impl @moon-plugin-api.Plugin for AlphaPlugin with fn on_enable(
  self : AlphaPlugin,
  ctx : @moon-plugin-api.PluginContext,
) -> Unit {
  let _ = self
  let _ = ctx
}

///|
impl @moon-plugin-api.Plugin for AlphaPlugin with fn on_disable(
  self : AlphaPlugin,
  ctx : @moon-plugin-api.PluginContext,
) -> Unit raise {
  let _ = self
  let _ = ctx
}

///|
struct BetaPlugin {
  version : String
}

///|
impl @moon-plugin-api.Plugin for BetaPlugin with fn descriptor(
  self : BetaPlugin,
) -> @moon-plugin-api.PluginDescriptor {
  {
    name: "beta",
    plugin_version: self.version,
    spec_version: 1,
    requires: ["alpha"],
    tables: ["registration", "reply"],
    migrations: [
      {
        version: 1,
        ddl: "CREATE TABLE `p_beta_registration` (`id` bigint NOT NULL, PRIMARY KEY (`id`))",
      },
    ],
    routes: [{ http_method: "POST", path: "/plugin/beta/ping", perms: [], perm_or: false, public: true }],
    menus: [],
    dicts: [],
  }
}

///|
impl @moon-plugin-api.Plugin for BetaPlugin with fn initialize(
  self : BetaPlugin,
  ctx : @moon-plugin-api.PluginContext,
) -> Unit raise {
  let _ = self
  let _ = ctx
}

///|
impl @moon-plugin-api.Plugin for BetaPlugin with fn on_enable(
  self : BetaPlugin,
  ctx : @moon-plugin-api.PluginContext,
) -> Unit {
  let _ = self
  let _ = ctx
}

///|
impl @moon-plugin-api.Plugin for BetaPlugin with fn on_disable(
  self : BetaPlugin,
  ctx : @moon-plugin-api.PluginContext,
) -> Unit raise {
  let _ = self
  let _ = ctx
}

///|
test "descriptor 验收：Array[&Plugin] 装两个异构实现并遍历 descriptor" {
  let a : &@moon-plugin-api.Plugin = AlphaPlugin::{ version: "1.0.0" }
  let b : &@moon-plugin-api.Plugin = BetaPlugin::{ version: "0.2.0" }
  let ps : Array[&@moon-plugin-api.Plugin] = [a, b]
  assert_eq(ps[0].descriptor().name, "alpha")
  assert_eq(ps[1].descriptor().name, "beta")
  assert_eq(ps[0].descriptor().plugin_version, "1.0.0")
  assert_eq(ps[1].descriptor().tables.length(), 2)
  assert_eq(ps[1].descriptor().migrations.length(), 1)
  assert_eq(ps[1].descriptor().migrations[0].version, 1)
}

///|
test "契约类型验收：MigrationDecl/RouteDecl/MenuDecl/DictDecl 字段齐全可构造" {
  let m : @moon-plugin-api.MigrationDecl = {
    version: 2,
    ddl: "ALTER TABLE `p_beta_registration` ADD COLUMN `note` varchar(255) NULL",
  }
  assert_eq(m.version, 2)
  let r : @moon-plugin-api.RouteDecl = {
    http_method: "GET",
    path: "/plugin/beta/list",
    perms: ["plugin:beta:list"],
    perm_or: false,
    public: false,
  }
  assert_eq(r.perms.length(), 1)
  let menu : @moon-plugin-api.MenuDecl = {
    code: "plugin:beta",
    title: "Beta",
    parent: "plugin",
    path: "/plugin/beta",
    component: "plugin/beta/index",
    icon: "bx",
    order: 9,
    btns: ["plugin:beta:add"],
    force: false,
  }
  assert_eq(menu.btns.length(), 1)
  let d : @moon-plugin-api.DictDecl = {
    code: "plugin_beta_status",
    name: "Beta 状态",
    group_code: "plugin",
    items: [
      { code: "1", name: "启用", sort: 1 },
      { code: "2", name: "停用", sort: 2 },
    ],
  }
  assert_eq(d.items.length(), 2)
}
