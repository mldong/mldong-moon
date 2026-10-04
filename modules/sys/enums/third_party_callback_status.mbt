// 第三方回调处理状态（boot2 ThirdPartyCallbackHandleStatusEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let cb_untreated : @core.IntVal = { code: 0, label: "未处理" }

///|
pub let cb_succeeded : @core.IntVal = { code: 1, label: "处理成功" }

///|
pub let cb_failed : @core.IntVal = { code: 2, label: "处理失败" }

///|
pub fn third_party_callback_status_all() -> Array[@core.IntVal] {
  [cb_untreated, cb_succeeded, cb_failed]
}
