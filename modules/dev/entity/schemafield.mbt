// dev_schema_field 实体 —— 纯数据，零框架类型；类名去表前缀（dev_schema_field → SchemaField）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct SchemaField {
  mut id : Int64
  mut schema_id : Int64
  mut field_name : String
  mut remark : String
  mut field_size : Int?
  mut data_type : String?
  mut is_primary : Int?
  mut nullable : Int?
  mut default_value : String?
  mut component : String?
  mut sort : Int64?
  mut variable : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
  mut is_deleted : Int?
}
