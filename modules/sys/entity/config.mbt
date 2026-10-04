// sys_config 实体 —— 纯数据，零框架类型；类名去表前缀（sys_config → Config）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct Config {
  mut id : Int64
  mut name : String
  mut code : String
  mut group_code : String
  mut content : String?
  mut is_sys : Int?
  mut enabled : Int?
  mut remark : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
  mut is_deleted : Int?
}
