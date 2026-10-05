// sys_sms_template 表编解码器 —— BaseDao 模板的每实体配置〔cmd/gen 生成，可手改〕

///|
let smstemplate_table : TableCodec[@entity.SmsTemplate] = TableCodec::{
  name: "sys_sms_template",
  cols: [
    "id",
    "biz_type",
    "template_code",
    "provider",
    "content",
    "signature",
    "enabled",
    "remark",
    "create_user",
    "create_time",
    "update_user",
    "update_time",
    "is_deleted",
  ],
  insert_cols: [
    { name: "id", get: fn(d) { L(d.id) } },
    { name: "biz_type", get: fn(d) { I(d.biz_type) } },
    { name: "template_code", get: fn(d) { S(d.template_code) } },
    { name: "provider", get: fn(d) { S(d.provider) } },
    { name: "content", get: fn(d) { S(d.content) } },
    { name: "signature", get: fn(d) { opt_s(d.signature) } },
    { name: "enabled", get: fn(d) { opt_i(d.enabled) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "create_time", get: fn(d) { S(match d.create_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "update_time", get: fn(d) { S(match d.update_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "create_user", get: fn(d) { opt_l(d.create_user) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  update_cols: [
    { name: "biz_type", get: fn(d) { I(d.biz_type) } },
    { name: "template_code", get: fn(d) { S(d.template_code) } },
    { name: "provider", get: fn(d) { S(d.provider) } },
    { name: "content", get: fn(d) { S(d.content) } },
    { name: "signature", get: fn(d) { opt_s(d.signature) } },
    { name: "enabled", get: fn(d) { opt_i(d.enabled) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "update_time", get: fn(_d) { S(@core.now_str()) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  from_row: row_smstemplate,
  id_of: fn(d) { L(d.id) },
  del_col: Some("is_deleted"),
  order_col: "create_time",
}

///|
/// 行映射按列名取 —— MyBatis resultMap 的手写对应物
fn row_smstemplate(r : @moondb.Row) -> @entity.SmsTemplate {
  {
    id: row_i64(r, "id"),
    biz_type: row_int_d(r, "biz_type", 0),
    template_code: row_text(r, "template_code", ""),
    provider: row_text(r, "provider", ""),
    content: row_text(r, "content", ""),
    signature: row_opt_text(r, "signature"),
    enabled: row_opt_int(r, "enabled"),
    remark: row_opt_text(r, "remark"),
    create_user: row_opt_i64(r, "create_user"),
    create_time: row_opt_text(r, "create_time"),
    update_user: row_opt_i64(r, "update_user"),
    update_time: row_opt_text(r, "update_time"),
    is_deleted: row_opt_int(r, "is_deleted"),
  }
}
