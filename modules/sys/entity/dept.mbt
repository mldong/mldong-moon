// sys_dept 实体 —— 纯数据，零框架类型；类名去表前缀（sys_dept → Dept）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct Dept {
  mut id : Int64
  mut parent_id : Int64?
  mut pids : String?
  mut name : String
  mut code : String
  mut sort : Int64?
  mut enabled : Int?
  mut leader_ids : String?
  mut main_leader_id : Int64?
  mut remark : String?
  mut variable : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
  mut is_deleted : Int?
}
