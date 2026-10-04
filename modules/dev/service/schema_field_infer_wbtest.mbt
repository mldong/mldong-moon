// 字段推断器 + 拖拽排序算法 —— 白盒测试（纯函数直跑，零 IO）

///|
/// Json 对象取键（builtin Json 无 op_get；测试专用）
fn jget(v : Json, k : String) -> Json {
  match v {
    Object(map) =>
      match map.get(k) {
        Some(x) => x
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
test "sql_type_to_enum_code：goframe 同表 port 码表" {
  assert_eq(sql_type_to_enum_code("varchar", 64), @enums.dt_string.code)
  assert_eq(sql_type_to_enum_code("char", 1), @enums.dt_string.code)
  assert_eq(sql_type_to_enum_code("json", 0), @enums.dt_string.code)
  assert_eq(sql_type_to_enum_code("text", 0), @enums.dt_clob.code)
  assert_eq(sql_type_to_enum_code("longtext", 0), @enums.dt_clob.code)
  assert_eq(sql_type_to_enum_code("int", 11), @enums.dt_integer.code)
  assert_eq(sql_type_to_enum_code("tinyint", 1), @enums.dt_boolean.code) // tinyint(1)=布尔
  assert_eq(sql_type_to_enum_code("tinyint", 4), @enums.dt_integer.code)
  assert_eq(sql_type_to_enum_code("smallint", 6), @enums.dt_short.code)
  assert_eq(sql_type_to_enum_code("bigint", 20), @enums.dt_long.code)
  assert_eq(sql_type_to_enum_code("decimal", 10), @enums.dt_big_decimal.code)
  assert_eq(sql_type_to_enum_code("datetime", 0), @enums.dt_local_dt.code)
  assert_eq(sql_type_to_enum_code("timestamp", 0), @enums.dt_timestamp.code)
  assert_eq(sql_type_to_enum_code("date", 0), @enums.dt_local_date.code)
  assert_eq(sql_type_to_enum_code("blob", 0), @enums.dt_blob.code)
  assert_eq(sql_type_to_enum_code("unknown_x", 0), @enums.dt_string.code) // 兜底 String
}

///|
test "infer_component：boot2 inferComponent 分支序" {
  // id 早支在 infer_field_config，不在组件层
  assert_eq(infer_component(@enums.dt_string.code, "user_name", 64), "Input")
  assert_eq(infer_component(@enums.dt_string.code, "remark", 64), "Textarea") // UC-0309 备注语义
  assert_eq(infer_component(@enums.dt_string.code, "intro", 500), "Textarea") // >200
  assert_eq(infer_component(@enums.dt_clob.code, "content", 0), "Textarea")
  assert_eq(infer_component(@enums.dt_long.code, "process_instance_id", 20), "TableLink")
  assert_eq(infer_component(@enums.dt_long.code, "dept_id", 20), "ApiTreeSelect")
  assert_eq(infer_component(@enums.dt_long.code, "user_id", 20), "ApiSelect")
  assert_eq(infer_component(@enums.dt_integer.code, "status", 4), "ApiDict")
  assert_eq(infer_component(@enums.dt_integer.code, "age", 4), "InputNumber")
  assert_eq(infer_component(@enums.dt_boolean.code, "is_deleted_x", 1), "ApiDict")
  assert_eq(infer_component(@enums.dt_local_date.code, "birthday", 0), "DatePicker")
  assert_eq(infer_component(@enums.dt_local_dt.code, "create_time", 0), "DatePicker")
  // Upload 只落 default 分支（STRING>200 先中 Textarea，boot2/goframe 同序）；未知类型码走 default
  assert_eq(infer_component(@enums.dt_string.code, "avatar", 255), "Textarea")
  assert_eq(infer_component(999, "avatar", 255), "Upload")
  assert_eq(infer_component(999, "attachment", 255), "Upload")
}

///|
test "infer_field_ext：ext 形状（必填/搜索/字典/关联/日期）" {
  // 非主键常规：Input + LIKE 搜索 + 必填推断（name）
  let ext2 = infer_field_ext(@enums.dt_string.code, "user_name", 64, "Input", "sys_user")
  assert_eq(jget(ext2, "required"), Json::number(1.0)) // 含 name → 必填
  assert_eq(jget(ext2, "searchType"), Json::string("LIKE"))
  assert_eq(jget(ext2, "search"), Json::number(1.0))
  // ApiDict 布尔：yes_no + RadioGroup
  let ext3 = infer_field_ext(@enums.dt_boolean.code, "enabled", 1, "ApiDict", "sys_config")
  assert_eq(jget(ext3, "ApiDict_code"), Json::string("yes_no"))
  assert_eq(jget(ext3, "ApiDict_renderType"), Json::string("RadioGroup"))
  // ApiDict 字典 code = {表名}_{字段名}
  let ext4 = infer_field_ext(@enums.dt_integer.code, "reason_type", 4, "ApiDict", "biz_leave")
  assert_eq(jget(ext4, "ApiDict_code"), Json::string("biz_leave_reason_type"))
  // ApiSelect 关联表映射（dict_id → sys/dict）
  let ext5 = infer_field_ext(@enums.dt_long.code, "dict_id", 20, "ApiSelect", "sys_dict_item")
  assert_eq(jget(ext5, "ApiSelect_api"), Json::string("/sys/dict/select"))
  // DatePicker 格式（datetime → 带时分秒）
  let ext6 = infer_field_ext(@enums.dt_local_dt.code, "create_time", 0, "DatePicker", "sys_user")
  assert_eq(jget(ext6, "DatePicker_valueFormat"), Json::string("YYYY-MM-DD HH:mm:ss"))
  // date → 纯日期
  let ext7 = infer_field_ext(@enums.dt_local_date.code, "birthday", 0, "DatePicker", "sys_user")
  assert_eq(jget(ext7, "DatePicker_valueFormat"), Json::string("YYYY-MM-DD"))
  // UC-0309：数字列可排序 + 默认列宽
  assert_eq(jget(ext5, "columnWidth"), Json::number(120.0))
}

///|
test "infer_id_ext：主键/id 早支隐藏" {
  let ext1 = infer_id_ext()
  assert_eq(jget(ext1, "listHide"), Json::number(1.0))
  assert_eq(jget(ext1, "viewHide"), Json::number(1.0))
  assert_eq(jget(ext1, "Input_type"), Json::string("hidden"))
  assert_eq(jget(ext1, "addHide"), Json::number(0.0))
  // infer_field_config 早支走同一形状（出口为 variable 字符串）
  let (c1, v1) = infer_field_config(true, "id", @enums.dt_long.code, 20, "sys_user")
  assert_eq(c1, "Input")
  assert_true(v1.contains("listHide"))
}

///|
test "命名派生：moduleName/tableCamelName/className/fieldCamel" {
  assert_eq(@dto.module_name_of("sys_user"), "sys")
  assert_eq(@dto.module_name_of("bare"), "")
  assert_eq(@dto.table_camel_name_of("sys_user"), "user")
  assert_eq(@dto.table_camel_name_of("sys_dict_item"), "dictItem")
  assert_eq(@dto.table_camel_name_of("bare"), "bare")
  assert_eq(@dto.class_name_of("sys_dict_item"), "DictItem")
  assert_eq(@dto.camel_case("user_name"), "userName")
  assert_eq(@dto.camel_case("id"), "id")
}

///|
test "drag_sort_plan：boot2 updateSort 三分支" {
  // 场景 1：往下拖（index 0 → 2），hover 行 -1，hover 之后其余 +1
  let p1 = drag_sort_plan([11L, 12L, 13L], [0L, 1L, 2L], 11L, 13L)
  assert_eq(p1[0], (11L, 2L)) // 拖拽行取 hover sort
  assert_eq(p1[1], (13L, 1L)) // hover 行 -1（往下拖）
  assert_eq(p1[2], (12L, 0L)) // hover 之前的其余行 -1（boot2 i<hoverRowIndex）
  // 场景 2：往上拖（index 2 → 0），hover 行 +1，hover 之前的其余行 -1
  let p2 = drag_sort_plan([11L, 12L, 13L], [0L, 1L, 2L], 13L, 11L)
  assert_eq(p2[0], (13L, 0L))
  assert_eq(p2[1], (11L, 1L)) // hover 行 +1（往上拖）
  assert_eq(p2[2], (12L, 2L)) // hover 之后的其余行 +1（boot2 i>hoverRowIndex）
  // 无操作：同 id / 空清单
  assert_true(drag_sort_plan([11L], [0L], 11L, 11L).is_empty())
  assert_true(drag_sort_plan([], [], 1L, 2L).is_empty())
}

///|
test "parse_field_size：column_type 提长度" {
  assert_eq(parse_field_size("varchar(64)"), Some(64))
  assert_eq(parse_field_size("bigint(20)"), Some(20))
  assert_eq(parse_field_size("int"), None)
  assert_eq(parse_field_size("datetime"), None)
  assert_eq(parse_field_size("decimal(10,2)"), None) // 逗号非数字 → None
}
