// sys_message 实体 —— 纯数据，零框架类型；类名去表前缀（sys_message → Message）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct Message {
  mut id : Int64
  mut title : String
  mut content : String?
  mut msg_type : Int
  mut biz_type : String
  mut biz_id : Int64?
  mut receiver_user_id : Int64
  mut sender_user_id : Int64
  mut sender_name : String?
  mut url : String?
  mut variable : String?
  mut is_read : Int?
  mut create_user : Int64?
  mut create_time : String?
  mut update_user : Int64?
  mut update_time : String?
  mut is_deleted : Int?
}
