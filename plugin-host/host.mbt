// migration 应用器 —— 插件与框架基线（__framework__）共用一套。
// 算法逐步实现（勿自由发挥）：
//   幂等性来源是台账不是语句（MySQL 8.0 无 ADD COLUMN IF NOT EXISTS，重复 ADD 必撞 1060）；
//   一条 migration = 一条语句（多语句被服务端拒且零半执行——驱动硬约束）；
//   不包大事务——一条一语句＋"成功后才记账"已把半途失败定义成"重放那一条"，
//   套事务反而多出"回滚了但台账怎么算"的第三种状态；
//   失败即 raise（组名 + version + 驱动原文），不回滚、不重试、不补记。
// 两条纪律（反面教训通用化）：失败不得吞成恒成功；升级绝不重放整份基线——
// 幂等性来源是台账不是语句，IF NOT EXISTS 式短路只会把真错藏住。这里绝不重放已记账历史。

///|
/// 一个装载组：__framework__（框架基线增量）或一个插件。
pub(all) struct MigrationGroup {
  name : String // FRAMEWORK 保留名 或 插件名
  plugin_version : String
  spec_version : Int
  tables : Array[String] // 插件声明的表业务后缀（__framework__ 恒 []）；对账与 table_count 用
  migrations : Array[@api.MigrationDecl]
}

///|
/// 台账表自检 DDL（幂等，不依赖主脚本跑过；与 mysql-schema-all.sql 的两张表同形状）。
/// 台账被清（重跑基线脚本）能重建的是壳不是行——那个形状由三方对账拦成拒绝启动。
const CREATE_SYS_PLUGIN : String = "CREATE TABLE IF NOT EXISTS `sys_plugin` (`id` bigint(20) NOT NULL COMMENT '主键', `name` varchar(64) NOT NULL COMMENT '插件名 = 包名尾段 = /plugin/<name>/ = p_<name>_；保留值 __framework__', `plugin_version` varchar(32) NOT NULL COMMENT '插件版本（descriptor.plugin_version）', `spec_version` int(11) NOT NULL COMMENT '契约号（descriptor.spec_version），装载期比对，不匹配拒绝启动', `status` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1=enabled 2=disabled 3=orphan', `table_count` int(11) NOT NULL DEFAULT 0 COMMENT '声明的表数，对账用', `install_time` datetime(3) DEFAULT NULL COMMENT '最近一次装载成功时间', `create_user` bigint(20) DEFAULT NULL COMMENT '创建用户', `create_time` datetime(3) DEFAULT NULL COMMENT '创建时间', `update_user` bigint(20) DEFAULT NULL COMMENT '更新用户', `update_time` datetime(3) DEFAULT NULL COMMENT '更新时间', `remark` varchar(255) DEFAULT NULL COMMENT '备注（exec_raw 越界嫌疑等装载期审计挂这）', PRIMARY KEY (`id`), UNIQUE KEY `uk_plugin_name` (`name`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='插件台账（框架所有）'"

///|
const CREATE_SYS_PLUGIN_MIGRATION : String = "CREATE TABLE IF NOT EXISTS `sys_plugin_migration` (`id` bigint(20) NOT NULL COMMENT '主键', `plugin` varchar(64) NOT NULL COMMENT '插件名（含保留值 __framework__）', `version` int(11) NOT NULL COMMENT '组内单调递增，与 ddl_md5 一起做篡改检测', `ddl_md5` char(32) NOT NULL COMMENT '语句文本指纹；改历史必撞', `applied_time` datetime(3) DEFAULT NULL COMMENT '应用时间', `create_time` datetime(3) DEFAULT NULL COMMENT '创建时间', PRIMARY KEY (`id`), UNIQUE KEY `uk_plugin_version` (`plugin`, `version`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='migration 台账（append-only；插件与 __framework__ 同表同规则）'"

///|
/// descriptor → 装载组（插件 migrations 进 apply_all 的桥梁；__framework__ 组之外的各插件组）
pub fn descriptor_group(d : @api.PluginDescriptor) -> MigrationGroup {
  {
    name: d.name,
    plugin_version: d.plugin_version,
    spec_version: d.spec_version,
    tables: d.tables,
    migrations: d.migrations,
  }
}

///|
/// 语句文本指纹：统一 trim 后取 md5（人编辑文件补个换行不该误报篡改）。
/// ddl 归一化（trim）在装载点做，这里只对已归一文本取指纹。
pub fn ddl_md5(ddl : String) -> String {
  @core.md5_hex(ddl)
}

///|
/// 应用全部装载组：先 __framework__（插件的 DDL 可能依赖框架的新列），其余按名字典序。
/// 台账表自检 → 锁等待短超时 → 逐组应用（历史校验优先 → 只跑新增 → 成功立刻记账）→ upsert sys_plugin。
pub async fn apply_all(
  config : @core.MysqlConfig,
  groups : Array[MigrationGroup],
) -> Unit raise @core.MldongError {
  // 组校验：恰一个 __framework__；插件组名字不重
  let fw_count = groups.filter(fn(g) { g.name == FRAMEWORK }).length()
  if fw_count != 1 {
    raise @core.MldongError::Business(
      "装载组必须恰含一个 \{FRAMEWORK}，实得 \{fw_count}",
    )
  }
  let plugins = groups.filter(fn(g) { g.name != FRAMEWORK })
  plugins.sort_by(fn(a, b) { a.name.compare(b.name) })
  let seen : Map[String, Bool] = Map([], capacity=8)
  for g in plugins {
    if seen.get(g.name) is Some(_) {
      raise @core.MldongError::Business("装载组重名: \{g.name}")
    }
    seen[g.name] = true
  }
  let conn = @repo.open_conn(config)
  defer @repo.close_conn(conn)
  // 算法 1：台账表自检（幂等）
  let _ = @repo.x(conn, CREATE_SYS_PLUGIN, [])
  let _ = @repo.x(conn, CREATE_SYS_PLUGIN_MIGRATION, [])
  // 装载期自保：锁等待短超时（会话级可调实测过；失败时刻≈设定值+1s，预算按实测留）
  let _ = @repo.x(conn, "SET SESSION innodb_lock_wait_timeout = 5", [])
  // 算法 2：__framework__ 先行，其后按名字典序
  for g in groups {
    if g.name == FRAMEWORK {
      apply_group(conn, g)
    }
  }
  for g in plugins {
    apply_group(conn, g)
  }
}

///|
async fn apply_group(
  conn : @repo.MysqlBox,
  g : MigrationGroup,
) -> Unit raise @core.MldongError {
  // 组内归一：trim 一次，后续校验/执行/记账全用同一文本（指纹才对得上）
  let sorted : Array[@api.MigrationDecl] = g.migrations
    .copy()
    .map(fn(m) { { version: m.version, ddl: m.ddl.trim().to_owned() } })
  sorted.sort_by(fn(a, b) { a.version - b.version })
  for m in sorted {
    if m.version < 1 {
      raise @core.MldongError::Business(
        "装载组 \{g.name} 的 migration version 必须 ≥ 1（实得 \{m.version}）",
      )
    }
    if m.ddl.is_empty() {
      raise @core.MldongError::Business(
        "装载组 \{g.name} version \{m.version} 的 ddl 为空",
      )
    }
  }
  for i in 1..<sorted.length() {
    if sorted[i].version == sorted[i - 1].version {
      raise @core.MldongError::Business(
        "装载组 \{g.name} 内 migration 版本重号: \{sorted[i].version}",
      )
    }
  }
  // 算法 3：读该组台账 (version, ddl_md5) 全集
  let rows = @repo.q(
    conn,
    "SELECT version, ddl_md5 FROM sys_plugin_migration WHERE plugin = ? ORDER BY version",
    @repo.to_db_values([@core.S(g.name)]),
  )
  let ledger : Map[Int, String] = Map([], capacity=16)
  let mut max_v = 0
  for r in rows {
    let v = @repo.row_i64(r, "version").to_int()
    ledger[v] = @repo.row_text(r, "ddl_md5", "")
    if v > max_v {
      max_v = v
    }
  }
  // 算法 4：历史校验优先（改已应用的 ddl 文本 ⇒ 拒绝）
  for m in sorted {
    match ledger.get(m.version) {
      Some(recorded) =>
        if recorded != ddl_md5(m.ddl) {
          raise @core.MldongError::Business(
            "migration 历史校验失败: 组 \{g.name} version \{m.version} 已按其他文本应用（台账 md5=\{recorded}，现文本 md5=\{ddl_md5(m.ddl)}）——改历史必撞；先回滚这次文本改动，要改语义就追加新 version",
          )
        }
      None => ()
    }
  }
  // 算法 5：只应用 version > 台账最大值，每条单独 execute，成功后立刻记账（顺序不能倒）
  let mut applied = 0
  for m in sorted {
    if m.version > max_v {
      if g.name == FRAMEWORK && m.version <= BASELINE_NO {
        // 基线脚本快照已含（新库从脚本建好即有该变更），重放会撞 1060 ⇒ 只补台账。
        // 残余风险契约见 BASELINE_NO 注释：跨版本升级没跑过中间装载器的库须重跑新基线脚本。
        println(
          "[plugin-host] \{g.name} v\{m.version} ≤ 基线号 \{BASELINE_NO}，基线脚本已含：仅补台账不执行",
        )
      } else {
        let _ = @repo.x(conn, m.ddl, []) catch {
          e =>
            raise @core.MldongError::Business(
              "migration 应用失败: 组 \{g.name} version \{m.version} — \{@core.MldongError::message(e)}（不回滚不重试；台账无此 version ⇒ 修好 DDL 后重放是设计允许的；有此 version 但 md5 不等 ⇒ 人工介入）",
            )
        }
      }
      record_applied(conn, g.name, m.version, ddl_md5(m.ddl))
      applied += 1
    }
  }
  println("[plugin-host] 组 \{g.name} 应用 \{applied} 条（台账已有 \{max_v} 为最高版本）")
  // 算法 7：组成功后 upsert sys_plugin（__framework__ 也落一行，巡检/对账用）
  let now = @core.now_str()
  let _ = @repo.x(
    conn,
    "INSERT INTO sys_plugin (id, name, plugin_version, spec_version, status, table_count, install_time, create_user, create_time, update_user, update_time) VALUES (?, ?, ?, ?, 1, ?, ?, NULL, ?, NULL, ?) ON DUPLICATE KEY UPDATE plugin_version = VALUES(plugin_version), spec_version = VALUES(spec_version), status = 1, table_count = VALUES(table_count), install_time = VALUES(install_time), update_time = VALUES(update_time)",
    @repo.to_db_values([
      @core.L(@core.next_id()),
      @core.S(g.name),
      @core.S(g.plugin_version),
      @core.I(g.spec_version),
      @core.I(g.tables.length()),
      @core.S(now),
      @core.S(now),
      @core.S(now),
    ]),
  ) catch {
    e =>
      raise @core.MldongError::Business(
        "sys_plugin 台账 upsert 失败: 组 \{g.name} — \{@core.MldongError::message(e)}",
      )
  }
}

///|
async fn record_applied(
  conn : @repo.MysqlBox,
  plugin : String,
  version : Int,
  md5 : String,
) -> Unit raise @core.MldongError {
  let now = @core.now_str()
  let _ = @repo.x(
    conn,
    "INSERT INTO sys_plugin_migration (id, plugin, version, ddl_md5, applied_time, create_time) VALUES (?, ?, ?, ?, ?, ?)",
    @repo.to_db_values([
      @core.L(@core.next_id()),
      @core.S(plugin),
      @core.I(version),
      @core.S(md5),
      @core.S(now),
      @core.S(now),
    ]),
  ) catch {
    e =>
      raise @core.MldongError::Business(
        "migration 台账记账失败: 组 \{plugin} version \{version} — \{@core.MldongError::message(e)}（DDL 可能已生效但未记账 ⇒ 修好库后重放会撞 1060/1050，设计允许）",
      )
  }
}
