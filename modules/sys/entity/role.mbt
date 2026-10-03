// sys_role 实体 —— 纯数据，零框架类型；类名去表前缀（sys_role → Role）

///|
pub(all) struct Role {
  mut id : Int64
  app_code : String?
  name : String
  code : String
  mut sort : Int64?
  mut role_type : Int?
  mut enabled : Int
  mut data_scope : Int?
  mut remark : String?
  mut create_time : String?
  mut update_time : String?
  mut is_deleted : Int?
}
