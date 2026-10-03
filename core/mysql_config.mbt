// MySQL 连接配置 —— 纯配置结构 + env 读取（零驱动依赖；连接动作在 dao-mysql 层）
// 凭据只走 MLDONG_DB_* env，默认值不含密码（开源仓红线）

///|
pub(all) struct MysqlConfig {
  host : String
  port : Int
  user : String
  password : String
  database : String
}

///|
pub fn MysqlConfig::from_env() -> MysqlConfig {
  let port : Int = match @env.get_env_var("MLDONG_DB_PORT") {
    Some(s) =>
      try {
        @string.parse_int(s)
      } catch {
        _ => 3306
      }
    None => 3306
  }
  {
    host: @env.get_env_var("MLDONG_DB_HOST").unwrap_or("127.0.0.1"),
    port,
    user: @env.get_env_var("MLDONG_DB_USER").unwrap_or("root"),
    password: @env.get_env_var("MLDONG_DB_PWD").unwrap_or(""),
    database: @env.get_env_var("MLDONG_DB_NAME").unwrap_or("mldong-moon"),
  }
}
