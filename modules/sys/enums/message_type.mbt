// 站内消息类型（boot2 MessageTypeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let todo : @core.IntVal = { code: 10, label: "待办消息" }

///|
pub let notice : @core.IntVal = { code: 20, label: "通知消息" }

///|
pub fn message_type_all() -> Array[@core.IntVal] {
  [todo, notice]
}
