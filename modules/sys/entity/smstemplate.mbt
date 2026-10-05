// sys_sms_template 实体 —— 纯数据，零框架类型；类名去表前缀（sys_sms_template → SmsTemplate）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct SmsTemplate {
  mut id : Int64
  mut biz_type : Int
  mut template_code : String
  mut provider : String
  mut content : String
  mut signature : String?
  mut enabled : Int?
  mut remark : String?
  mut create_user : Int64?
  mut create_time : String?
  mut update_user : Int64?
  mut update_time : String?
  mut is_deleted : Int?
}
