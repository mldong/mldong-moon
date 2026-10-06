// sys_vis_log 表编解码器 —— BaseDao 模板的每实体配置〔cmd/gen 生成，可手改〕

///|
let vislog_table : TableCodec[@entity.VisLog] = TableCodec::{
  name: "sys_vis_log",
  cols: [
    "id",
    "name",
    "success",
    "message",
    "ip",
    "location",
    "browser",
    "os",
    "vis_type",
    "vis_time",
    "account",
    "sign_value",
  ],
  insert_cols: [
    { name: "id", get: fn(d) { L(d.id) } },
    { name: "name", get: fn(d) { opt_s(d.name) } },
    { name: "success", get: fn(d) { opt_s(d.success) } },
    { name: "message", get: fn(d) { opt_s(d.message) } },
    { name: "ip", get: fn(d) { opt_s(d.ip) } },
    { name: "location", get: fn(d) { opt_s(d.location) } },
    { name: "browser", get: fn(d) { opt_s(d.browser) } },
    { name: "os", get: fn(d) { opt_s(d.os) } },
    { name: "vis_type", get: fn(d) { I(d.vis_type) } },
    { name: "vis_time", get: fn(d) { opt_s(d.vis_time) } },
    { name: "account", get: fn(d) { opt_s(d.account) } },
    { name: "sign_value", get: fn(d) { opt_s(d.sign_value) } },
  ],
  update_cols: [
    { name: "name", get: fn(d) { opt_s(d.name) } },
    { name: "success", get: fn(d) { opt_s(d.success) } },
    { name: "message", get: fn(d) { opt_s(d.message) } },
    { name: "ip", get: fn(d) { opt_s(d.ip) } },
    { name: "location", get: fn(d) { opt_s(d.location) } },
    { name: "browser", get: fn(d) { opt_s(d.browser) } },
    { name: "os", get: fn(d) { opt_s(d.os) } },
    { name: "vis_type", get: fn(d) { I(d.vis_type) } },
    { name: "vis_time", get: fn(d) { opt_s(d.vis_time) } },
    { name: "account", get: fn(d) { opt_s(d.account) } },
    { name: "sign_value", get: fn(d) { opt_s(d.sign_value) } },
  ],
  from_row: row_vislog,
  id_of: fn(d) { L(d.id) },
  del_col: None,
  order_col: "id",
}

///|
/// 行映射按列名取 —— 手写行映射（无反射）
fn row_vislog(r : @moondb.Row) -> @entity.VisLog {
  {
    id: row_i64(r, "id"),
    name: row_opt_text(r, "name"),
    success: row_opt_text(r, "success"),
    message: row_opt_text(r, "message"),
    ip: row_opt_text(r, "ip"),
    location: row_opt_text(r, "location"),
    browser: row_opt_text(r, "browser"),
    os: row_opt_text(r, "os"),
    vis_type: row_int_d(r, "vis_type", 0),
    vis_time: row_opt_text(r, "vis_time"),
    account: row_opt_text(r, "account"),
    sign_value: row_opt_text(r, "sign_value"),
  }
}
