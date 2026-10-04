// 管理员类型（boot2 AdminTypeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let super_admin : @core.IntVal = { code: 1, label: "超级管理员" }

///|
pub let common_admin : @core.IntVal = { code: 2, label: "普通管理员" }

///|
pub fn admin_type_all() -> Array[@core.IntVal] {
  [super_admin, common_admin]
}
