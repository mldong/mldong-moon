// 在册对账 + 装载期归属闸（装载收口的一次 DB 现读）。
// 两方（10-09 owner 拍 C：装载器不带 schema 通道，与 13 栈库面重合）：
//   代码方 = cmd/main/plugins.mbt 里注册的 descriptor（编译进去的就是事实）
//   库方   = information_schema.tables 的本库全表集（现读，不照脚本文本抄数——
//            同一内容在脚本里出现过两种写法，抄一次固化一次错）
// 原第三"记录方"（sys_plugin / sys_plugin_migration 两张台账）随 schema 通道一起撤销：
// 插件表的 DDL 归 doc/sql/mysql-schema-all.sql（与 modules 同法），装载器不建表、不记账，
// 只判"声明合法 + 声明在册"。缺表不再自动补建 ⇒ 这正是把它砍成对账器的取舍：
// 装坏不再可能被静默吸收，但升级要人动手改脚本。
// 不一致一律拒绝启动，不静默降级（静默跳过＝装坏没人知道）；消息点名缺/多的是哪些表——
// 这是唯一能让人 30 秒定位的东西。⚠ wasm 档 abort 消息不落日志，调用方（cmd/main）
// 必须 println 后再 abort。

///|
/// 装载校验入口：库方一次现读 → 契约号比对 → 归属闸 → 在册对账。
/// contract_prefixes = 装配级契约路由前缀白名单（官方契约插件用，如 ["/wf/"]）。
pub async fn load_check(
  config : @core.MysqlConfig,
  plugins : Array[&@api.Plugin],
  contract_prefixes : Array[String],
) -> Unit raise @core.MldongError {
  let conn = @repo.open_conn(config)
  defer @repo.close_conn(conn)
  // 库方一次现读：本库全表名
  let rows = @repo.q(
    conn,
    // 别名必写：MySQL 8.0 的 information_schema 列标签是大写（TABLE_NAME），5.7 是小写；
    // 这里读空 ⇒ 库方全表集为空 ⇒ 归属闸与在册对账整个失能（10-08 一键栈实测）。
    "SELECT table_name AS table_name FROM information_schema.tables WHERE table_schema = DATABASE()",
    [],
  )
  let db_tables : Map[String, Bool] = Map([], capacity=64)
  for r in rows {
    let name = @repo.row_text(r, "table_name", "")
    if !name.is_empty() {
      db_tables[name] = true
    }
  }
  // 框架黑名单 = 全表集去掉 p_*（插件命名空间）——归属闸的输入
  let framework_tables : Array[String] = []
  for k in db_tables.keys() {
    if !(k.length() >= 2 && k[0:2].to_owned() == "p_") {
      framework_tables.push(k)
    }
  }
  let descriptors : Array[@api.PluginDescriptor] = plugins.map(fn(p) { p.descriptor() })
  // 契约号比对（卡 0：spec_version 装载期比对，不匹配拒绝启动）
  for d in descriptors {
    if d.spec_version != @api.SPEC_VERSION {
      raise @core.MldongError::Business(
        "契约号不匹配: 插件 \{d.name} spec_version=\{d.spec_version}，装载器要求 \{@api.SPEC_VERSION}——插件与装载器版本错配，先对齐再启动",
      )
    }
  }
  let gate : OwnershipGate = { framework_tables, plugins: descriptors, contract_prefixes }
  gate.validate()
  reconcile_registered(descriptors, db_tables)
}

///|
/// 在册对账（纯函数，零 DB 可测）：两向都必须成立——
/// ①声明的 p_<name>_<suffix> 库里有（装载器不建表，缺表 ⇒ 拒）；
/// ②库里每张 p_* 都在某个 descriptor 的声明集里（无主 p_ 表 ⇒ 拒，含摘注册的残留与
///   声明被删而表留下）。所有权按"声明集全等"判，不按前缀松判——
///   否则 tables=[] 的在册插件自己的残留表正好检不出。
pub fn reconcile_registered(
  descriptors : Array[@api.PluginDescriptor],
  db_tables : Map[String, Bool],
) -> Unit raise @core.MldongError {
  let declared : Map[String, String] = Map([], capacity=8) // "p_<name>_<suffix>" → owner
  for d in descriptors {
    for suffix in d.tables {
      declared["p_\{d.name}_\{suffix}"] = d.name
    }
  }
  // ① 声明在册
  for d in descriptors {
    let missing : Array[String] = []
    for suffix in d.tables {
      let full = "p_\{d.name}_\{suffix}"
      if db_tables.get(full) is None {
        missing.push(full)
      }
    }
    if !missing.is_empty() {
      let ms = missing.join(",")
      raise @core.MldongError::Business(
        "在册对账失败: 插件 \{d.name} 声明的表 [\{ms}] 在本库不存在——装载器不建表（schema 通道已撤），DDL 归 doc/sql/mysql-schema-all.sql；处置 = 把该表补进基线脚本并重建库，或从 descriptor.tables 摘掉这条声明",
      )
    }
  }
  // ② 无主 p_ 表
  let orphans : Array[String] = []
  for t in db_tables.keys() {
    if t.length() >= 2 && t[0:2].to_owned() == "p_" && declared.get(t) is None {
      orphans.push(t)
    }
  }
  if !orphans.is_empty() {
    let known : Array[String] = []
    for d in descriptors {
      known.push(d.name)
    }
    orphans.sort()
    let os = orphans.join(",")
    let ks = known.join(",")
    raise @core.MldongError::Business(
      "在册对账失败（残留）: 库里的插件表 [\{os}] 不属任何在册插件（在册 = [\{ks}]）；处置 = 先落回注册再按声明清表，或确认是手工建的孤儿表后整库清理",
    )
  }
}
