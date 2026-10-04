// 任务队列状态（boot2 TaskExecutionQueueStateEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let not_started : @core.IntVal = { code: 0, label: "未开始" }

///|
pub let executing : @core.IntVal = { code: 1, label: "执行中" }

///|
pub let retry_pending : @core.IntVal = { code: 9, label: "执行失败-待重试" }

///|
pub fn task_queue_state_all() -> Array[@core.IntVal] {
  [not_started, executing, retry_pending]
}
