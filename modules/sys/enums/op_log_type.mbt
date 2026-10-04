// 系统日志操作类型（boot2 OpLogTypeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let op_login : @core.IntVal = { code: 0, label: "登录" }

///|
pub let op_query : @core.IntVal = { code: 1, label: "查询" }

///|
pub let op_add : @core.IntVal = { code: 2, label: "新增" }

///|
pub let op_update : @core.IntVal = { code: 3, label: "修改" }

///|
pub let op_delete : @core.IntVal = { code: 4, label: "删除" }

///|
pub let op_logout : @core.IntVal = { code: 5, label: "主动注销" }

///|
pub fn op_log_type_all() -> Array[@core.IntVal] {
  [op_login, op_query, op_add, op_update, op_delete, op_logout]
}
