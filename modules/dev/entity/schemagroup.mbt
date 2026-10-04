// dev_schema_group 实体 —— 纯数据，零框架类型；类名去表前缀（dev_schema_group → SchemaGroup）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct SchemaGroup {
  mut id : Int64
  mut name : String
  mut code : String
  mut icon : String?
  mut sort : Int64?
  mut remark : String?
  mut variable : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
  mut is_deleted : Int?
}
