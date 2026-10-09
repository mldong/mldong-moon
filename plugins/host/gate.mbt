// 表归属闸（装载期）—— 不变式不是"前缀"，是"一张表只能有一个所有者"。
// 三档归属：own（插件拥有，p_<name>_ 由装载器拼）/ framework（基线表，information_schema
// 现读，不照脚本文本抄数——脚本有两种写法，抄一次固化一次错）/ collision（他人 p_<other>_）。
// 防误用不防恶意（单用户连接防不住恶意），但"不给裸 Conn"那档是可用性防护——见 ScopedDb。
// 装载器不开 schema 通道（10-09 owner 拍 C）：插件表的 DDL 归 doc/sql/mysql-schema-all.sql，
// 本闸只判"声明得合不合法"；"声明了但库里有没有"归 reconcile 的在册对账。

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
  }
}

///|
/// 插件名形状 ^[a-z][a-z0-9_]{1,31}$——手写字符检查（MoonBit core 正则是方言，
/// 字符类里 [:-] 非法等坑）。形状本身已排掉旧保留组名 `__framework__`（首字符须小写字母），
/// 装载器不再有组名概念，故不另设保留名。
pub fn validate_name(name : String) -> Unit raise @core.MldongError {
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
