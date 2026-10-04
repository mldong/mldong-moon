// sys_file_info 实体 —— 纯数据，零框架类型；类名去表前缀（sys_file_info → FileInfo）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct FileInfo {
  mut id : Int64
  mut url : String
  mut size : Int64?
  mut size_info : String?
  mut filename : String?
  mut original_filename : String?
  mut base_path : String?
  mut path : String?
  mut ext : String?
  mut content_type : String?
  mut platform : String?
  mut th_url : String?
  mut th_filename : String?
  mut th_size : Int64?
  mut th_size_info : String?
  mut th_content_type : String?
  mut object_id : String?
  mut object_type : String?
  mut attr : String?
  mut create_time : String?
  mut create_user : Int64?
  mut update_time : String?
  mut update_user : Int64?
}
