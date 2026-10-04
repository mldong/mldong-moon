// sys_menu 实体 —— 纯数据，零框架类型；类名去表前缀（sys_menu → Menu）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct Menu {
  mut id : Int64
  mut app_code : String?
  mut parent_id : Int64?
  mut name : String
  mut code : String
  mut pids : String?
  mut menu_type : Int?
  mut sort : Int64?
  mut path : String?
  mut component : String?
  mut icon : String?
  mut is_show : Int?
  mut is_link : Int?
  mut url : String?
  mut enabled : Int?
  mut open_type : Int?
  mut is_cache : Int?
  mut is_sync : Int?
  mut variable : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
  mut is_deleted : Int?
}
