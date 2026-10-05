// sys_sms_log 实体 —— 纯数据，零框架类型；类名去表前缀（sys_sms_log → SmsLog）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct SmsLog {
  mut id : Int64
  mut task_id : Int64?
  mut phone : String
  mut biz_type : Int
  mut provider : String?
  mut content : String?
  mut status : Int?
  mut error_msg : String?
  mut cost_ms : Int?
  mut client_ip : String?
  mut create_time : String?
  mut update_time : String?
}
