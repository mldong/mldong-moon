// sys_user 实体 —— 纯数据，零框架类型；类名去表前缀（sys_user → User）

///|
pub(all) struct User {
  mut id : Int64
  user_name : String
  real_name : String
  mut nick_name : String?
  mut avatar : String?
  mut password : String?
  mut salt : String?
  mut mobile_phone : String?
  mut tel : String?
  mut email : String?
  mut admin_type : Int?
  mut sex : Int?
  mut is_locked : Int?
  mut dept_id : Int64?
  mut post_id : Int64?
  mut remark : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
  mut is_deleted : Int?
}

///|
/// 关联查询行：user + dept/post 名称（对齐 boot2 selectCustom 的 UserVO 投影）
pub(all) struct UserPageRow {
  user : User
  dept_name : String?
  dept_code : String?
  post_name : String?
  post_code : String?
}
