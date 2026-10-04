// sys_dict_item 实体 —— 纯数据，零框架类型；类名去表前缀（sys_dict_item → DictItem）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct DictItem {
  mut id : Int64
  mut dict_id : Int64
  mut name : String
  mut code : String
  mut sort : Int64?
  mut enabled : Int?
  mut remark : String?
  mut variable : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
  mut is_deleted : Int?
}
