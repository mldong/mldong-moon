// parse_order_by 白名单行为（UC-0430 排序契约）——白盒测试

///|
test "parse_order_by 正常解析 + desc 方向" {
  let orders = parse_order_by({ "orderBy": "sort desc, id" })
  assert_eq(orders.length(), 2)
  assert_eq(orders[0].0, "sort")
  assert_eq(orders[0].1, true)
  assert_eq(orders[1].0, "id")
  assert_eq(orders[1].1, false)
}

///|
test "parse_order_by 白名单：注入串整段静默丢弃" {
  let orders = parse_order_by({ "orderBy": "sort;drop table sys_dict" })
  assert_eq(orders.length(), 0)
}

///|
test "parse_order_by camel 列名 snake 化 + 缺省正序" {
  let orders = parse_order_by({ "orderBy": "createTime" })
  assert_eq(orders.length(), 1)
  assert_eq(orders[0].0, "create_time")
  assert_eq(orders[0].1, false)
}
