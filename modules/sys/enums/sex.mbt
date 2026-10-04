// 性别（boot2 SexEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let man : @core.IntVal = { code: 1, label: "男" }

///|
pub let woman : @core.IntVal = { code: 2, label: "女" }

///|
pub let unknown : @core.IntVal = { code: 3, label: "未知" }

///|
pub fn sex_all() -> Array[@core.IntVal] {
  [man, woman, unknown]
}
