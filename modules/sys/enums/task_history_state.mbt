// 历史归档队列状态（boot2 TaskExecutionHistoryStateEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let th_succeeded : @core.IntVal = { code: 2, label: "成功" }

///|
pub let th_cancelled : @core.IntVal = { code: 3, label: "已取消" }

///|
pub let th_failed : @core.IntVal = { code: 9, label: "失败-终态" }

///|
pub fn task_history_state_all() -> Array[@core.IntVal] {
  [th_succeeded, th_cancelled, th_failed]
}
