// 角色数据范围（boot2 RoleDataScopeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let all_data : @core.IntVal = { code: 1, label: "全部数据权限" }

///|
pub let custom_data : @core.IntVal = { code: 2, label: "自定义数据权限" }

///|
pub let dept_data : @core.IntVal = { code: 3, label: "本部门数据权限" }

///|
pub let dept_and_sub_data : @core.IntVal = { code: 4, label: "本部门及以下部门权限" }

///|
pub let self_data : @core.IntVal = { code: 5, label: "仅本人数据权限" }

///|
pub fn role_data_scope_all() -> Array[@core.IntVal] {
  [all_data, custom_data, dept_data, dept_and_sub_data, self_data]
}
