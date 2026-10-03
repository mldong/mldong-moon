// 密码件单测 —— md5 向量为公开标准值（hutool SecureUtil.md5 同式：UTF-8 小写 hex）

///|
test "md5_hex 标准向量" {
  assert_eq(@moon-core.md5_hex(""), "d41d8cd98f00b204e9800998ecf8427e")
  assert_eq(@moon-core.md5_hex("123456"), "e10adc3949ba59abbe56e057f20f883e")
  assert_eq(@moon-core.md5_hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
}

///|
test "random_salt 形状：8 位小写字母+数字" {
  for _ in 0..<20 {
    let s = @moon-core.random_salt()
    assert_eq(s.length(), 8)
    for i in 0..<8 {
      match s.get_char(i) {
        Some(c) => {
          let v = c.to_int()
          assert_true(
            (v >= 0x61 && v <= 0x7A) || (v >= 0x30 && v <= 0x39),
          )
        }
        None => abort("盐越界")
      }
    }
  }
}

///|
test "password_matches：md5(明文+盐) 匹配与缺件不匹配" {
  let salt = "abc12345"
  let hash = @moon-core.md5_hex("123456" + salt)
  assert_true(@moon-core.password_matches("123456", Some(hash), Some(salt)))
  assert_false(@moon-core.password_matches("wrong", Some(hash), Some(salt)))
  // 错盐必不匹配
  assert_false(@moon-core.password_matches("123456", Some(hash), Some("zzzzzzzz")))
  // 缺件（存量脏数据）一律不匹配
  assert_false(@moon-core.password_matches("123456", None, Some(salt)))
  assert_false(@moon-core.password_matches("123456", Some(hash), None))
}
