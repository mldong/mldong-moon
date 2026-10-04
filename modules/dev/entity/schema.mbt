// dev_schema 实体 —— 纯数据，零框架类型；类名去表前缀（dev_schema → Schema）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct Schema {
  mut id : Int64
  mut schema_group_id : Int64?
  mut table_name : String
  mut remark : String
  mut other_remark : String?
  mut table_type : Int?
  mut form_type : Int?
  mut is_tree : Int?
  mut sort : Int64?
  mut icon : String?
  mut search_form_keys : String?
  mut list_keys : String?
  mut variable : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
  mut is_deleted : Int?
}
