// 是否（boot2 YesNoEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let yes : @core.IntVal = { code: 1, label: "是" }

///|
pub let no : @core.IntVal = { code: 0, label: "否" }

///|
pub fn yes_no_all() -> Array[@core.IntVal] {
  [yes, no]
}
