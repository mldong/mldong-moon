// sys_op_log 实体 —— 纯数据，零框架类型；类名去表前缀（sys_op_log → OpLog）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct OpLog {
  mut id : Int64
  mut name : String?
  mut op_type : Int?
  mut success : String?
  mut message : String?
  mut ip : String?
  mut location : String?
  mut browser : String?
  mut os : String?
  mut url : String?
  mut class_name : String?
  mut method_name : String?
  mut req_method : String?
  mut param : String?
  mut result : String?
  mut op_time : String?
  mut account : String?
  mut play_user_account : String?
  mut request_no : String?
  mut sign_value : String?
}
