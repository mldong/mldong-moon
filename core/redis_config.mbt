// Redis 连接配置 —— 纯配置结构 + env 读取（零驱动依赖；连接动作在 cmd/main 装配处）
// 凭据只走 MLDONG_REDIS_* env，默认值不含密码（开源仓红线）

///|
pub(all) struct RedisConfig {
  host : String
  port : Int
  password : String
  db : Int
}

///|
pub fn RedisConfig::from_env() -> RedisConfig {
  let port : Int = match @env.get_env_var("MLDONG_REDIS_PORT") {
    Some(s) =>
      try {
        @string.parse_int(s)
      } catch {
        _ => 6379
      }
    None => 6379
  }
  let db : Int = match @env.get_env_var("MLDONG_REDIS_DB") {
    Some(s) =>
      try {
        @string.parse_int(s)
      } catch {
        _ => 0
      }
    None => 0
  }
  {
    host: @env.get_env_var("MLDONG_REDIS_HOST").unwrap_or("127.0.0.1"),
    port,
    password: @env.get_env_var("MLDONG_REDIS_PWD").unwrap_or(""),
    db,
  }
}
