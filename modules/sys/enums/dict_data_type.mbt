// 字典数据类型（boot2 DictDataType 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let dt_string : @core.IntVal = { code: 1, label: "字符串" }

///|
pub let dt_integer : @core.IntVal = { code: 2, label: "整型" }

///|
pub fn dict_data_type_all() -> Array[@core.IntVal] {
  [dt_string, dt_integer]
}
