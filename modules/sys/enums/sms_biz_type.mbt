// 短信业务类型（boot2 SmsBizTypeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let sms_register : @core.IntVal = { code: 10, label: "注册验证码" }

///|
pub let sms_login : @core.IntVal = { code: 20, label: "登录验证码" }

///|
pub let sms_reset_pwd : @core.IntVal = { code: 30, label: "重置密码" }

///|
pub let sms_change_info : @core.IntVal = { code: 40, label: "变更验证码" }

///|
pub let sms_bind : @core.IntVal = { code: 50, label: "绑定验证码" }

///|
pub let sms_notify : @core.IntVal = { code: 60, label: "通知消息" }

///|
pub fn sms_biz_type_all() -> Array[@core.IntVal] {
  [sms_register, sms_login, sms_reset_pwd, sms_change_info, sms_bind, sms_notify]
}
