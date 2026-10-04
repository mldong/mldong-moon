// EnumDictRegistry 注册中心契约（goframe GetEnums/FindInEnumMapModel 同位）——白盒测试

///|
test "register/list/find + 重复 key 覆盖不追加" {
  let r = EnumDictRegistry::new()
  r.register({ name: "是否", dict_key: "yes_no", data_type: Some(2), items: [] })
  r.register({ name: "性别", dict_key: "sex", data_type: Some(2), items: [] })
  assert_eq(r.list().length(), 2)
  // 重复注册：覆盖原项，不追加
  r.register({ name: "是否v2", dict_key: "yes_no", data_type: Some(2), items: [] })
  assert_eq(r.list().length(), 2)
  assert_eq(r.find("yes_no").unwrap().name, "是否v2")
  // 未注册 key → None（回退链走下一级）
  assert_true(r.find("no_such") is None)
}
