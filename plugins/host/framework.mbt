// __framework__ 基线增量组 —— doc/sql/migrations/*.sql 装载期读入（async/fs 真读，
// 本仓 fileinfo 上传同款运行期文件通道）。
// 目录契约（反面教训：升级＝重跑整份基线脚本，新 DDL 会被 IF NOT EXISTS 静默短路、真变更永远不落地）：
//   - 一个文件一条语句（驱动硬约束）；文件名 NNNN_说明.sql，version = 前导数字段；
//   - 目录只增不删不改：改历史必撞 md5；
//   - 合并（把增量固化进 mysql-schema-all.sql）时不删文件、只抬 BASELINE_NO。

///|
/// 契约号：descriptor.spec_version 装载期比对，不匹配拒绝启动；破坏性契约变更时 +1
pub const SPEC_VERSION : Int = 5 // 4→5：RouteDecl 增 perm_or——工作流族 13 栈的 OR 语义须由声明方带（moon 侧 10-08 补齐引擎 DefaultActionPermissionProvider 同位映射）
// 2→3：PluginContext 增 dicts 自定义字典贡献面（UC-0432，10-07 集成轮）
// 1→2：PluginContext 增 sys_query 框架查询面字段（10-07）

///|
/// mysql-schema-all.sql 已固化的最高 framework migration 版本。
/// 合并规则：把 1..N 固化进基线脚本后这里改 N；应用器对 version ≤ N 且台账缺失的条目
/// 只补台账不执行（新库从脚本建好即含该变更，重放会撞 1060）。
/// 残余风险（已知并接受，写进处置契约）：库里是更老基线建的表 + 中间几版从未跑过装载器
/// ⇒ 补台账会声称已应用而表里实际没有。处置 = 跨版本升级时重跑新基线脚本
/// （重跑后由装载校验的三方对账拦成拒绝启动，不会静默）。
pub const BASELINE_NO : Int = 0

///|
/// 框架保留组名（sys_plugin.name / sys_plugin_migration.plugin 的保留值）
pub const FRAMEWORK : String = "__framework__"

///|
/// 从目录装载 framework 组：只收 .sql，version 取文件名前导数字段；
/// 重号 / 缺口 / 目录缺失 / 文件空 / 基线号超前 都在装载期拒绝。
pub async fn framework_group(dir : String) -> MigrationGroup raise @core.MldongError {
  let names = @fs.readdir(dir, sort=true) catch {
    e =>
      raise @core.MldongError::Internal(
        "__framework__ 迁移目录不可读: \{dir} — \{e}",
      )
  }
  let decls : Array[@api.MigrationDecl] = []
  for name in names {
    let n = name.length()
    if !(n >= 4 && name[n - 4:n].to_owned() == ".sql") {
      continue
    }
    let version = parse_migration_version(name)
    let path = dir + "/" + name
    let data = @fs.read_file(path) catch {
      e =>
        raise @core.MldongError::Internal("__framework__ 迁移文件不可读: \{path} — \{e}")
    }
    let text = data.text() catch {
      e =>
        raise @core.MldongError::Business(
          "__framework__ 迁移文件不是合法 UTF-8 文本: \{path} — \{e}",
        )
    }
    // DDL 归一：trim（指纹与执行用同一文本；文件尾多个换行不该误报篡改）
    let ddl = text.trim().to_owned()
    if ddl.is_empty() {
      raise @core.MldongError::Business("__framework__ 迁移文件为空: \{name}")
    }
    decls.push({ version, ddl })
  }
  // 重号/缺口校验：目录只增不删，版本必须连续覆盖 1..max
  decls.sort_by(fn(a, b) { a.version - b.version })
  let mut prev = 0
  for d in decls {
    if d.version == prev {
      raise @core.MldongError::Business(
        "__framework__ 迁移版本重号: \{d.version}（一个号只能一个文件）",
      )
    }
    if d.version != prev + 1 {
      raise @core.MldongError::Business(
        "__framework__ 迁移版本缺口: 期望 \{prev + 1} 实得 \{d.version}（目录只增不删；缺文件多半是合并后误删，先补文件）",
      )
    }
    prev = d.version
  }
  if BASELINE_NO > prev {
    raise @core.MldongError::Business(
      "__framework__ 基线号 \{BASELINE_NO} 超过迁移目录最大版本 \{prev}（脚本固化到 N 就必须存在 1..N 的文件——合并只抬 BASELINE_NO 不删文件）",
    )
  }
  {
    name: FRAMEWORK,
    plugin_version: "framework",
    spec_version: SPEC_VERSION,
    tables: [],
    migrations: decls,
  }
}

///|
/// 文件名前导数字段 → version（"0007_wf_x.sql" → 7）；
/// 无前导数字段 / 数字段后不是下划线 / 空串形状都拒。
pub fn parse_migration_version(name : String) -> Int raise @core.MldongError {
  let len = name.length()
  let mut i = 0
  while i < len {
    match name.get_char(i) {
      Some(c) =>
        if c >= '0' && c <= '9' {
          i += 1
        } else {
          break
        }
      None => break
    }
  }
  if i == 0 || i >= len || name.get_char(i) != Some('_') {
    raise @core.MldongError::Business(
      "__framework__ 迁移文件名不合法: \{name}（形状 = NNNN_说明.sql，version 取前导数字段）",
    )
  }
  let mut v = 0
  for k in 0..<i {
    v = v * 10 + (name.get_char(k).unwrap().to_int() - 0x30)
  }
  v
}
