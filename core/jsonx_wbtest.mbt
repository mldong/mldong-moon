// ext_json_opt 空不出键语义（UC-0426 双读侧）——白盒测试

///|
test "ext_json_opt 非空对象 Some" {
  let j = ext_json_opt(Some("{\"i18n\":{\"zh-CN\":\"a\"}}"))
  assert_true(j is Some(_))
}

///|
test "ext_json_opt 空对象/NULL/坏串/空串 None" {
  assert_true(ext_json_opt(Some("{}")) is None)
  assert_true(ext_json_opt(None) is None)
  assert_true(ext_json_opt(Some("not-json")) is None)
  assert_true(ext_json_opt(Some("")) is None)
  assert_true(ext_json_opt(Some("[1,2]")) is None)
}
