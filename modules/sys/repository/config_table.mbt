// sys_config 表编解码器 —— BaseDao 模板的每实体配置〔cmd/gen 生成，可手改〕

///|
let config_table : TableCodec[@entity.Config] = TableCodec::{
  name: "sys_config",
  cols: [
    "id",
    "name",
    "code",
    "group_code",
    "content",
    "is_sys",
    "enabled",
    "remark",
    "create_time",
    "create_user",
    "update_time",
    "update_user",
    "is_deleted",
  ],
  insert_cols: [
    { name: "id", get: fn(d) { L(d.id) } },
    { name: "name", get: fn(d) { S(d.name) } },
    { name: "code", get: fn(d) { S(d.code) } },
    { name: "group_code", get: fn(d) { S(d.group_code) } },
    { name: "content", get: fn(d) { opt_s(d.content) } },
    { name: "is_sys", get: fn(d) { opt_i(d.is_sys) } },
    { name: "enabled", get: fn(d) { opt_i(d.enabled) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "create_time", get: fn(d) { S(match d.create_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "update_time", get: fn(d) { S(match d.update_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "create_user", get: fn(d) { opt_l(d.create_user) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  update_cols: [
    { name: "name", get: fn(d) { S(d.name) } },
    { name: "code", get: fn(d) { S(d.code) } },
    { name: "group_code", get: fn(d) { S(d.group_code) } },
    { name: "content", get: fn(d) { opt_s(d.content) } },
    { name: "is_sys", get: fn(d) { opt_i(d.is_sys) } },
    { name: "enabled", get: fn(d) { opt_i(d.enabled) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "update_time", get: fn(_d) { S(@core.now_str()) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  from_row: row_config,
  id_of: fn(d) { L(d.id) },
  del_col: Some("is_deleted"),
  order_col: "create_time",
}

///|
/// 行映射按列名取 —— MyBatis resultMap 的手写对应物
fn row_config(r : @moondb.Row) -> @entity.Config {
  {
    id: row_i64(r, "id"),
    name: row_text(r, "name", ""),
    code: row_text(r, "code", ""),
    group_code: row_text(r, "group_code", ""),
    content: row_opt_text(r, "content"),
    is_sys: row_opt_int(r, "is_sys"),
    enabled: row_opt_int(r, "enabled"),
    remark: row_opt_text(r, "remark"),
    create_time: row_opt_text(r, "create_time"),
    create_user: row_opt_i64(r, "create_user"),
    update_time: row_opt_text(r, "update_time"),
    update_user: row_opt_i64(r, "update_user"),
    is_deleted: row_opt_int(r, "is_deleted"),
  }
}
