// 定时任务状态（boot2 TimerStateEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let running : @core.IntVal = { code: 1, label: "运行" }

///|
pub let stop : @core.IntVal = { code: 2, label: "停止" }

///|
pub fn timer_state_all() -> Array[@core.IntVal] {
  [running, stop]
}
