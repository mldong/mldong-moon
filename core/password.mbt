// 密码散列与盐 —— 对齐 boot2 口径：md5(密码明文 + 盐) 小写 hex（hutool SecureUtil.md5 同物），
// 盐 = 8 位小写字母+数字随机串（hutool RandomUtil.randomString 同字母表）。
// 默认密码机制对齐 boot2 save/resetPwd：新建/重置用户发 DEFAULT_PASSWORD，不收用户自报密码。

///|
/// 新建/重置用户的默认密码明文（boot2 ConstantContextHolder.getDefaultPassword() 同位；
/// 各语言实现各自有配置机制，骨架先常量，TODO 接 sys_config/env）
pub const DEFAULT_PASSWORD : String = "123456"

///|
/// md5 小写 hex 32（UTF-8 字节；boot2 SecureUtil.md5(String) 同物）
pub fn md5_hex(s : String) -> String {
  let digest = @md5.hash(@utf8.encode(s).exact_view())
  bytes_lower_hex(digest)
}

///|
/// 8 位盐：小写字母 + 数字（hutool RandomUtil.randomString(8) 同字母表）
pub fn random_salt() -> String {
  let charset = "abcdefghijklmnopqrstuvwxyz0123456789"
  let rand = @random.Rand::new()
  let buf = StringBuilder()
  for _ in 0..<8 {
    let idx = rand.int(limit=charset.length())
    match charset.get_char(idx) {
      Some(c) => buf.write_char(c)
      None => ()
    }
  }
  buf.to_string()
}

///|
/// 字节 → 小写 hex
fn bytes_lower_hex(b : Bytes) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder()
  for i in 0..<b.length() {
    let v = b[i].to_int()
    match digits.get_char(v >> 4) {
      Some(c) => buf.write_char(c)
      None => ()
    }
    match digits.get_char(v & 0xF) {
      Some(c) => buf.write_char(c)
      None => ()
    }
  }
  buf.to_string()
}

///|
///# 密码是否匹配（存量校验）：md5(明文 + 盐) == 存储散列
/// 任一缺件（未设密码/未设盐）一律不匹配。
pub fn password_matches(plain : String, stored_hash : String?, salt : String?) -> Bool {
  match (stored_hash, salt) {
    (Some(hash), Some(salt)) => md5_hex("\{plain}\{salt}") == hash
    _ => false
  }
}
