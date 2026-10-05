// sys_task_execution_history 实体 —— 纯数据，零框架类型；类名去表前缀（sys_task_execution_history → TaskExecutionHistory）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct TaskExecutionHistory {
  mut id : Int64
  mut task_name : String
  mut spring_bean_name : String
  mut biz_id : Int64
  mut task_state : Int?
  mut finished_time : String?
  mut allow_max_error_count : Int?
  mut error_count : Int?
  mut error_reason : String?
  mut variable : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
}
