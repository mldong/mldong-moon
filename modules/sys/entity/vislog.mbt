// sys_vis_log 实体 —— 纯数据，零框架类型；类名去表前缀（sys_vis_log → VisLog）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct VisLog {
  mut id : Int64
  mut name : String?
  mut success : String?
  mut message : String?
  mut ip : String?
  mut location : String?
  mut browser : String?
  mut os : String?
  mut vis_type : Int
  mut vis_time : String?
  mut account : String?
  mut sign_value : String?
}
