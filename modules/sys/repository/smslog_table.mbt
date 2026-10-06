// sys_sms_log 表编解码器 —— BaseDao 模板的每实体配置〔cmd/gen 生成，可手改〕

///|
let smslog_table : TableCodec[@entity.SmsLog] = TableCodec::{
  name: "sys_sms_log",
  cols: [
    "id",
    "task_id",
    "phone",
    "biz_type",
    "provider",
    "content",
    "status",
    "error_msg",
    "cost_ms",
    "client_ip",
    "create_time",
    "update_time",
  ],
  insert_cols: [
    { name: "id", get: fn(d) { L(d.id) } },
    { name: "task_id", get: fn(d) { opt_l(d.task_id) } },
    { name: "phone", get: fn(d) { S(d.phone) } },
    { name: "biz_type", get: fn(d) { I(d.biz_type) } },
    { name: "provider", get: fn(d) { opt_s(d.provider) } },
    { name: "content", get: fn(d) { opt_s(d.content) } },
    { name: "status", get: fn(d) { opt_i(d.status) } },
    { name: "error_msg", get: fn(d) { opt_s(d.error_msg) } },
    { name: "cost_ms", get: fn(d) { opt_i(d.cost_ms) } },
    { name: "client_ip", get: fn(d) { opt_s(d.client_ip) } },
    { name: "create_time", get: fn(d) { S(match d.create_time { Some(s) => s; None => @core.now_str() }) } },
  ],
  update_cols: [
    { name: "task_id", get: fn(d) { opt_l(d.task_id) } },
    { name: "phone", get: fn(d) { S(d.phone) } },
    { name: "biz_type", get: fn(d) { I(d.biz_type) } },
    { name: "provider", get: fn(d) { opt_s(d.provider) } },
    { name: "content", get: fn(d) { opt_s(d.content) } },
    { name: "status", get: fn(d) { opt_i(d.status) } },
    { name: "error_msg", get: fn(d) { opt_s(d.error_msg) } },
    { name: "cost_ms", get: fn(d) { opt_i(d.cost_ms) } },
    { name: "client_ip", get: fn(d) { opt_s(d.client_ip) } },
    { name: "update_time", get: fn(_d) { S(@core.now_str()) } },
  ],
  from_row: row_smslog,
  id_of: fn(d) { L(d.id) },
  del_col: None,
  order_col: "create_time",
}

///|
/// 行映射按列名取 —— 手写行映射（无反射）
fn row_smslog(r : @moondb.Row) -> @entity.SmsLog {
  {
    id: row_i64(r, "id"),
    task_id: row_opt_i64(r, "task_id"),
    phone: row_text(r, "phone", ""),
    biz_type: row_int_d(r, "biz_type", 0),
    provider: row_opt_text(r, "provider"),
    content: row_opt_text(r, "content"),
    status: row_opt_int(r, "status"),
    error_msg: row_opt_text(r, "error_msg"),
    cost_ms: row_opt_int(r, "cost_ms"),
    client_ip: row_opt_text(r, "client_ip"),
    create_time: row_opt_text(r, "create_time"),
    update_time: row_opt_text(r, "update_time"),
  }
}
