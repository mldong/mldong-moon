// sys_sms_template MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct SmsTemplateRepository {
  base : BaseDao[@entity.SmsTemplate]
}

///|
pub fn SmsTemplateRepository::make(config : @core.MysqlConfig) -> SmsTemplateRepository {
  { base: { config, table: smstemplate_table } }
}

///|
pub impl @dao.SmsTemplateDao for SmsTemplateRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.SmsTemplateDao for SmsTemplateRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.SmsTemplateDao for SmsTemplateRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.SmsTemplateDao for SmsTemplateRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.SmsTemplateDao for SmsTemplateRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.SmsTemplateDao for SmsTemplateRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

///|
/// biz_type+provider 唯一前置校验（DB uk_biz_type_provider 同语义，友好报 99999999）
pub impl @dao.SmsTemplateDao for SmsTemplateRepository with fn check_unique(
  self,
  biz_type,
  provider,
  exclude_id,
  msg,
) {
  let conn = open_conn(self.base.config)
  let rows = match exclude_id {
    Some(ex) => q(
      conn,
      "SELECT COUNT(*) AS c FROM sys_sms_template WHERE biz_type = ? AND provider = ? AND is_deleted = 0 AND id <> ?",
      [@moondb.Int(biz_type), @moondb.Text(provider), @moondb.Int64(ex)],
    )
    None => q(
      conn,
      "SELECT COUNT(*) AS c FROM sys_sms_template WHERE biz_type = ? AND provider = ? AND is_deleted = 0",
      [@moondb.Int(biz_type), @moondb.Text(provider)],
    )
  }
  conn.close()
  if !rows.is_empty() && row_int_d(rows[0], "c", 0) > 0 {
    raise @core.MldongError::InvalidParam(msg)
  }
}

pub extend SmsTemplateRepository with @dao.SmsTemplateDao::{
  check_unique,
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
}
