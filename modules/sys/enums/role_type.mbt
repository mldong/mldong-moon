// 角色类型（boot2 RoleTypeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let common_role : @core.IntVal = { code: 1, label: "普通角色" }

///|
pub let data_role : @core.IntVal = { code: 2, label: "数据角色" }

///|
pub let workflow_role : @core.IntVal = { code: 3, label: "工作流" }

///|
pub fn role_type_all() -> Array[@core.IntVal] {
  [common_role, data_role, workflow_role]
}
