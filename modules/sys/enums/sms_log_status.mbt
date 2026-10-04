// 短信发送日志状态（boot2 SmsLogStatusEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let pending : @core.IntVal = { code: 0, label: "待发送" }

///|
pub let success : @core.IntVal = { code: 1, label: "成功" }

///|
pub let failed : @core.IntVal = { code: 2, label: "失败" }

///|
pub fn sms_log_status_all() -> Array[@core.IntVal] {
  [pending, success, failed]
}
