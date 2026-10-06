// 三方对账 + 装载期归属闸（装载收口的一次 DB 现读）。
// 三方：代码方 = 注册进 cmd/main 的 descriptor（编译进去的就是事实）；
//       记录方 = sys_plugin / sys_plugin_migration；
//       库方 = information_schema.tables 的 p_<name>_% 实际存在集（黑名单现读，
//       不照脚本文本抄数——同一内容在脚本里出现过两种写法，抄一次固化一次错）。
// 不一致一律拒绝启动，不静默降级（静默跳过＝装坏没人知道）；消息点名缺/多的是哪一方、
// 哪些表——唯一能让人 30 秒定位的东西。⚠ wasm 档 abort 消息不落日志，调用方（cmd/main）
// 必须 println 后再 abort。

///|
/// 装载校验入口：归属闸 → 三方对账 → 基线号对账。
/// fw_max_version = __framework__ 迁移目录最高版本（装载方已保证 BASELINE_NO ≤ 它）。
pub async fn load_check(
  config : @core.MysqlConfig,
  plugins : Array[&@api.Plugin],
  fw_max_version : Int,
) -> Unit raise @core.MldongError {
  let conn = @repo.open_conn(config)
  defer @repo.close_conn(conn)
  // 库方一次现读：本库全表名
  let rows = @repo.q(
    conn,
    "SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE()",
    [],
  )
  let all_tables : Map[String, Bool] = Map([], capacity=64)
  for r in rows {
    let name = @repo.row_text(r, "table_name", "")
    if !name.is_empty() {
      all_tables[name] = true
    }
  }
  // 框架黑名单 = 全表集去掉 p_*（插件命名空间）；这是归属闸与"残留表"判定的共同输入
  let framework_tables : Array[String] = []
  for k in all_tables.keys() {
    if !(k.length() >= 2 && k[0:2].to_owned() == "p_") {
      framework_tables.push(k)
    }
  }
  // ④ 归属闸（含两两冲突校验 + migration 目标表扫描）
  let descriptors : Array[@api.PluginDescriptor] = plugins.map(fn(p) { p.descriptor() })
  let gate : OwnershipGate = { framework_tables, plugins: descriptors }
  gate.validate()
  // 记录方现读：sys_plugin 全集 + 逐插件 migration 计数
  let reg_rows = @repo.q(conn, "SELECT name FROM sys_plugin", [])
  let registered : Map[String, Bool] = Map([], capacity=8)
  for r in reg_rows {
    let name = @repo.row_text(r, "name", "")
    if !name.is_empty() {
      registered[name] = true
    }
  }
  let mig_rows = @repo.q(
    conn,
    "SELECT plugin, COUNT(*) AS n FROM sys_plugin_migration GROUP BY plugin",
    [],
  )
  let ledger : Map[String, Int] = Map([], capacity=8)
  for r in mig_rows {
    let name = @repo.row_text(r, "plugin", "")
    let n = @repo.row_i64(r, "n").to_int()
    if !name.is_empty() {
      ledger[name] = n
    }
  }
  // 基线号对账：__framework__ 台账最高版本（apply_all 补台账后）应 == 迁移目录最高版本。
  // 不等 = 台账被清而表在（重跑基线脚本清了台账）或目录被清——都拒绝启动。
  let mut fw_ledger_max = 0
  match ledger.get(FRAMEWORK) {
    Some(_) => {
      let vr = @repo.q(
        conn,
        "SELECT MAX(version) AS maxv FROM sys_plugin_migration WHERE plugin = ?",
        @repo.to_db_values([@core.S(FRAMEWORK)]),
      )
      if vr.length() > 0 {
        // MAX 空集回 NULL——先走文本读取器判 null（G：先判 null 再走类型化访问器）
        if @repo.row_text(vr[0], "maxv", "") != "" {
          fw_ledger_max = @repo.row_i64(vr[0], "maxv").to_int()
        }
      }
    }
    None => ()
  }
  if fw_ledger_max != fw_max_version {
    raise @core.MldongError::Business(
      "基线号对账失败: __framework__ 台账最高版本 \{fw_ledger_max} ≠ 迁移目录最高版本 \{fw_max_version}——库是拿旧脚本建的 / 台账被清而增量未补；处置 = 重跑新基线脚本后重启，或人工补台账",
    )
  }
  // 三方对账规则表（五行）
  for d in descriptors {
    let declared_full = d.tables.map(fn(s) { "p_\{d.name}_\{s}" })
    let is_registered = registered.get(d.name) is Some(_)
    // 库方：声明的 p_<name>_* 实际存在集
    let present : Array[String] = []
    let missing : Array[String] = []
    for t in declared_full {
      if all_tables.get(t) is Some(_) {
        present.push(t)
      } else {
        missing.push(t)
      }
    }
    if is_registered {
      if !missing.is_empty() {
        // 有 | 有 | 缺表 ⇒ orphan，拒绝启动
        let ms = missing.join(",")
        raise @core.MldongError::Business(
          "三方对账失败（orphan）: 插件 \{d.name} 缺表 [\{ms}]——表被手工 DROP；处置 = 卸载后重装该插件",
        )
      }
    } else {
      // 有 | 无 | 有表 ⇒ 需重装，拒绝启动
      if !present.is_empty() {
        let ps = present.join(",")
        raise @core.MldongError::Business(
          "三方对账失败（需重装）: 插件 \{d.name} 注册行缺失但表已存在 [\{ps}]（多半是重跑了基线脚本清了台账）；处置 = 重装该插件",
        )
      }
      // 有 | 无 | 无表 ⇒ 正常待装，继续（apply_all 会建）
    }
  }
  // 无 | 有 ⇒ 残留，拒绝启动
  for name in registered.keys() {
    if name == FRAMEWORK {
      continue
    }
    let mut known = false
    for d in descriptors {
      if d.name == name {
        known = true
      }
    }
    if !known {
      let mig_n = match ledger.get(name) {
        Some(n) => n
        None => 0
      }
      let tables_left : Array[String] = []
      let prefix = "p_\{name}_"
      for k in all_tables.keys() {
        if k.length() > prefix.length() && k[0:prefix.length()].to_owned() == prefix {
          tables_left.push(k)
        }
      }
      let ts = tables_left.join(",")
      raise @core.MldongError::Business(
        "三方对账失败（残留）: 插件 \{name} 注册行已摘但台账 \{mig_n} 条 + 表 \{tables_left.length()} 张 [\{ts}] 仍在；处置 = 先落回注册再正常卸载",
      )
    }
  }
}
