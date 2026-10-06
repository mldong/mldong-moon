// 表归属闸（装载期）—— 不变式不是"前缀"，是"一张表只能有一个所有者"。
// 三档归属：own（插件拥有，p_<name>_ 由装载器拼）/ framework（基线表，information_schema
// 现读，不照脚本文本抄数——脚本有两种写法，抄一次固化一次错）/ collision（他人 p_<other>_）。
// 防误用不防恶意（单用户连接防不住恶意），但"不给裸 Conn"那档是可用性防护——见 ScopedDb。

///|
/// 装载期归属闸的输入：框架黑名单（information_schema 现读）+ 本轮注册的全部 descriptor
/// + 契约路由前缀白名单（装配级；官方契约插件可声明白名单前缀下的路由，第三方仍锁 /plugin/<name>/）。
pub(all) struct OwnershipGate {
  framework_tables : Array[String] // 基线表全名（sys_*/wf_*/dev_*/biz_*…现读）
  plugins : Array[@api.PluginDescriptor]
  contract_prefixes : Array[String] // 如 ["/wf/"]；白名单前缀两两不撞（两插件同用一前缀即拒）
}

///|
/// 全量校验：任一违规即 raise，消息点名违规方（表名 / 插件名 / 路由），30 秒能定位。
pub fn OwnershipGate::validate(self : OwnershipGate) -> Unit raise @core.MldongError {
  let declared : Map[String, String] = Map([], capacity=8) // "p_<name>_<suffix>" → owner
  let claimed_prefix : Map[String, String] = Map([], capacity=4) // 契约前缀 → 插件名
  for p in self.plugins {
    validate_name(p.name)
    // 表命名空间段 = name（构造性）；声明后缀拼名后不得撞框架黑名单
    for suffix in p.tables {
      validate_suffix(suffix)
      let full = "p_\{p.name}_\{suffix}"
      if self.framework_tables.contains(full) {
        raise @core.MldongError::Business(
          "表归属冲突: 插件 \{p.name} 声明表 \{full} 撞框架基线表（框架所有，不许占用）",
        )
      }
      match declared.get(full) {
        Some(other) =>
          raise @core.MldongError::Business(
            "表归属冲突: \{full} 被两个插件声明（\{other} 与 \{p.name}）——一张表只能有一个所有者",
          )
        None => declared[full] = p.name
      }
    }
    // 路由闸：path 以 /plugin/<name>/ 开头，或命中装配级契约前缀白名单（如 /wf/，
    // 官方契约插件与 13 栈同一 URL 契约）；同一契约前缀只许一个插件使用
    let prefix = "/plugin/\{p.name}/"
    for r in p.routes {
      let ok_plugin = r.path.length() >= prefix.length() &&
        r.path[0:prefix.length()].to_owned() == prefix
      let mut ok_contract = false
      for cp in self.contract_prefixes {
        if r.path.length() >= cp.length() && r.path[0:cp.length()].to_owned() == cp {
          ok_contract = true
        }
      }
      if !(ok_plugin || ok_contract) {
        raise @core.MldongError::Business(
          "路由越界: 插件 \{p.name} 的路由 \{r.http_method} \{r.path} 不以 \{prefix} 开头也不在契约前缀白名单内",
        )
      }
    }
    for cp in self.contract_prefixes {
      let mut uses = false
      for r in p.routes {
        if r.path.length() >= cp.length() && r.path[0:cp.length()].to_owned() == cp {
          uses = true
        }
      }
      if uses {
        match claimed_prefix.get(cp) {
          Some(other) =>
            raise @core.MldongError::Business(
              "契约前缀冲突: \{cp} 被两个插件使用（\{other} 与 \{p.name}）",
            )
          None => claimed_prefix[cp] = p.name
        }
      }
    }
    // migration 目标表扫描（一条一语句 ⇒ 取 token 即可，不做完整 parser）
    for m in p.migrations {
      let targets = stmt_tables(m.ddl)
      if targets.is_empty() {
        raise @core.MldongError::Business(
          "migration 无法识别目标表: 插件 \{p.name} version \{m.version}（闸只认 CREATE/ALTER/DROP TABLE、CREATE/DROP INDEX .. ON、TRUNCATE）",
        )
      }
      for t in targets {
        let own_prefix = "p_\{p.name}_"
        if self.framework_tables.contains(t) {
          raise @core.MldongError::Business(
            "migration 越界: 插件 \{p.name} version \{m.version} 试图动框架表 \{t}（框架所有）",
          )
        }
        match declared.get(t) {
          Some(other) =>
            if other != p.name {
              raise @core.MldongError::Business(
                "migration 越界: 插件 \{p.name} version \{m.version} 试图动他人表 \{t}（所有者 \{other}）",
              )
            }
          None => ()
        }
        // 收紧档：未声明的 p_<name>_* 也拒——
        // 卸载清表只认声明集，migration 建了不声明的表 = 卸载残留洞
        if !(t.length() > own_prefix.length() && t[0:own_prefix.length()].to_owned() == own_prefix) {
          raise @core.MldongError::Business(
            "migration 越界: 插件 \{p.name} version \{m.version} 目标表 \{t} 不在本插件命名空间 p_\{p.name}_* 内",
          )
        }
        let suffix = t[own_prefix.length():].to_owned()
        if !p.tables.contains(suffix) {
          raise @core.MldongError::Business(
            "migration 与声明不符: 插件 \{p.name} version \{m.version} 目标表 \{t} 未在 tables 声明（声明了才能建，建了必须声明）",
          )
        }
      }
    }
  }
}

///|
/// 插件名形状 ^[a-z][a-z0-9_]{1,31}$——手写字符检查（MoonBit core 正则是方言，
/// 字符类里 [:-] 非法等坑）
pub fn validate_name(name : String) -> Unit raise @core.MldongError {
  if name == FRAMEWORK {
    raise @core.MldongError::Business("插件名 \{FRAMEWORK} 是装载器保留名")
  }
  let n = name.length()
  if n < 2 || n > 32 {
    raise @core.MldongError::Business("插件名长度须 2..32: \{name}")
  }
  let mut ok = true
  for i in 0..<n {
    match name.get_char(i) {
      Some(c) => {
        let v = c.to_int()
        let lower = v >= 0x61 && v <= 0x7A
        let digit = v >= 0x30 && v <= 0x39
        let underscore = v == 0x5F
        let legal = if i == 0 { lower } else { lower || digit || underscore }
        if !legal {
          ok = false
        }
      }
      None => ok = false
    }
  }
  if !ok {
    raise @core.MldongError::Business(
      "插件名形状不合法: \{name}（^[a-z][a-z0-9_]{1,31}$）",
    )
  }
}

///|
/// 表后缀形状：小写字母/数字/下划线，1..32（拼进 p_<name>_<suffix> 后整体仍受 64 名长约束）
fn validate_suffix(suffix : String) -> Unit raise @core.MldongError {
  let n = suffix.length()
  if n < 1 || n > 32 {
    raise @core.MldongError::Business("表后缀长度须 1..32: \{suffix}")
  }
  let mut ok = true
  for i in 0..<n {
    match suffix.get_char(i) {
      Some(c) => {
        let v = c.to_int()
        let lower = v >= 0x61 && v <= 0x7A
        let digit = v >= 0x30 && v <= 0x39
        let underscore = v == 0x5F
        if !(lower || digit || underscore) {
          ok = false
        }
      }
      None => ok = false
    }
  }
  if !ok {
    raise @core.MldongError::Business("表后缀形状不合法: \{suffix}")
  }
}

///|
/// 从一条 DDL 里提取目标表名（去 backtick、按标识符切 token、认六族语句形状）。
/// 一条一语句之后这就是取语句前几个 token 的事——不做完整 parser。
/// 认：CREATE [UNIQUE|FULLTEXT|SPATIAL] INDEX .. ON <t> / CREATE TABLE [IF NOT EXISTS] <t>
///    / ALTER TABLE [IF EXISTS] <t> / DROP TABLE [IF EXISTS] <t> / DROP INDEX <i> ON <t>
///    / TRUNCATE [TABLE] <t>
pub fn stmt_tables(ddl : String) -> Array[String] {
  // 标识符切分：字母/数字/下划线连续段为 token，其余为分隔符（backtick 一并当分隔符）
  let tokens : Array[String] = []
  let sb = StringBuilder()
  let mut emitting = false
  let n = ddl.length()
  for i in 0..=n {
    let mut c = ' '
    if i < n {
      match ddl.get_char(i) {
        Some(ch) => c = ch
        None => c = ' '
      }
    }
    let v = c.to_int()
    let alnum = (v >= 0x61 && v <= 0x7A) ||
      (v >= 0x41 && v <= 0x5A) ||
      (v >= 0x30 && v <= 0x39) ||
      v == 0x5F
    if alnum {
      sb.write_char(c)
      emitting = true
    } else if emitting {
      tokens.push(sb.to_string())
      sb.reset()
      emitting = false
    }
  }
  // 关键词扫描
  let targets : Array[String] = []
  let m = tokens.length()
  let mut i = 0
  while i < m {
    let t = tokens[i]
    if t == "CREATE" {
      // CREATE [UNIQUE|FULLTEXT|SPATIAL] INDEX <i> ON <t>  |  CREATE TABLE [IF NOT EXISTS] <t>
      let mut j = i + 1
      while j < m && (tokens[j] == "UNIQUE" || tokens[j] == "FULLTEXT" || tokens[j] == "SPATIAL") {
        j += 1
      }
      if j < m && tokens[j] == "INDEX" {
        // ON 之后的第一个 token
        let mut k = j + 2
        while k < m && tokens[k] != "ON" {
          k += 1
        }
        if k + 1 < m {
          targets.push(tokens[k + 1])
        }
        i = j + 2
      } else if j < m && tokens[j] == "TABLE" {
        let mut k = j + 1
        if k + 2 < m && tokens[k] == "IF" && tokens[k + 1] == "NOT" && tokens[k + 2] == "EXISTS" {
          k += 3
        }
        if k < m {
          targets.push(tokens[k])
        }
        i = k + 1
      } else {
        i += 1
      }
    } else if t == "ALTER" && i + 1 < m && tokens[i + 1] == "TABLE" {
      let mut k = i + 2
      if k + 1 < m && tokens[k] == "IF" && tokens[k + 1] == "EXISTS" {
        k += 2
      }
      if k < m {
        targets.push(tokens[k])
      }
      i = k + 1
    } else if t == "DROP" && i + 1 < m && tokens[i + 1] == "TABLE" {
      let mut k = i + 2
      if k + 1 < m && tokens[k] == "IF" && tokens[k + 1] == "EXISTS" {
        k += 2
      }
      if k < m {
        targets.push(tokens[k])
      }
      i = k + 1
    } else if t == "DROP" && i + 1 < m && tokens[i + 1] == "INDEX" {
      let mut k = i + 3
      while k < m && tokens[k] != "ON" {
        k += 1
      }
      if k + 1 < m {
        targets.push(tokens[k + 1])
      }
      i = k + 2
    } else if t == "TRUNCATE" {
      let mut k = i + 1
      if k < m && tokens[k] == "TABLE" {
        k += 1
      }
      if k < m {
        targets.push(tokens[k])
      }
      i = k + 1
    } else {
      i += 1
    }
  }
  targets
}
