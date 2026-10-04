// 配置常量 Holder —— boot2 ConstantContext/ConstantContextHolder 同位：
// 进程内 code→content 常量表，config 写路刷新，读取链 = **env 优先 → 常量表 → 默认值回填**。
// 消费方：默认密码（M_DEFAULT_PASSWORD）、验证码开关等系统参数——业务不直接查 sys_config 表。
// boot2 的定时刷新任务（RefreshConstantsTaskRunner）骨架先不做：写路即时刷新 + 多实例部署前补。

///|
pub(all) struct ConfigHolder {
  mut map : Map[String, String]
}

///|
pub fn ConfigHolder::new() -> ConfigHolder {
  { map: Map([], capacity=0) }
}

///|
/// 启动全量灌入（module 装配处调，取数闭包来自 config dao）
pub fn ConfigHolder::load_items(self : ConfigHolder, items : Array[@entity.Config]) -> Unit {
  for c in items {
    self.put(c.code, c.content)
  }
}

///|
/// 写路刷新（boot2 putConstant 同规则：code/value 任一空则忽略）
pub fn ConfigHolder::put(self : ConfigHolder, code : String, content : String?) -> Unit {
  if code.is_empty() {
    return
  }
  match content {
    Some(v) => if !v.is_empty() {
      let _ = self.map.set(code, v)
    }
    None => ()
  }
}

///|
/// 删除（remove 后由调用方刷新；boot2：系统常量在业务侧禁删，holder 只管摘）
pub fn ConfigHolder::delete(self : ConfigHolder, code : String) -> Unit {
  let _ = self.map.remove(code)
}

///|
/// 读链：env 优先（code 即环境变量名，boot2 getSysConfigWithDefault 同语义）→
/// 常量表 → 默认值（并回填常量表，boot2 同——后续读不再穿透）
pub fn ConfigHolder::get(self : ConfigHolder, code : String, default_value : String) -> String {
  match @env.get_env_var(code) {
    Some(v) => if !v.is_empty() {
      return v
    }
    None => ()
  }
  match self.map.get(code) {
    Some(v) => if !v.is_empty() {
      return v
    }
    None => ()
  }
  let _ = self.map.set(code, default_value)
  default_value
}
