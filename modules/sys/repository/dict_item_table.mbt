// sys_dict_item 表编解码器 —— BaseDao 模板的每实体配置〔cmd/gen 生成，可手改〕

///|
let dictitem_table : TableCodec[@entity.DictItem] = TableCodec::{
  name: "sys_dict_item",
  cols: [
    "id",
    "dict_id",
    "name",
    "code",
    "sort",
    "enabled",
    "remark",
    "variable",
    "create_time",
    "create_user",
    "update_time",
    "update_user",
    "is_deleted",
  ],
  insert_cols: [
    { name: "id", get: fn(d) { L(d.id) } },
    { name: "dict_id", get: fn(d) { L(d.dict_id) } },
    { name: "name", get: fn(d) { S(d.name) } },
    { name: "code", get: fn(d) { S(d.code) } },
    { name: "sort", get: fn(d) { opt_l(d.sort) } },
    { name: "enabled", get: fn(d) { opt_i(d.enabled) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "variable", get: fn(d) { opt_s(d.variable) } },
    { name: "create_time", get: fn(d) { S(match d.create_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "update_time", get: fn(d) { S(match d.update_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "create_user", get: fn(d) { opt_l(d.create_user) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  update_cols: [
    { name: "dict_id", get: fn(d) { L(d.dict_id) } },
    { name: "name", get: fn(d) { S(d.name) } },
    { name: "code", get: fn(d) { S(d.code) } },
    { name: "sort", get: fn(d) { opt_l(d.sort) } },
    { name: "enabled", get: fn(d) { opt_i(d.enabled) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "variable", get: fn(d) { opt_s(d.variable) } },
    { name: "update_time", get: fn(_d) { S(@core.now_str()) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  from_row: row_dictitem,
  id_of: fn(d) { L(d.id) },
  del_col: Some("is_deleted"),
  order_col: "create_time",
}

///|
/// 行映射按列名取 —— MyBatis resultMap 的手写对应物
fn row_dictitem(r : @moondb.Row) -> @entity.DictItem {
  {
    id: row_i64(r, "id"),
    dict_id: row_i64(r, "dict_id"),
    name: row_text(r, "name", ""),
    code: row_text(r, "code", ""),
    sort: row_opt_i64(r, "sort"),
    enabled: row_opt_int(r, "enabled"),
    remark: row_opt_text(r, "remark"),
    variable: row_opt_text(r, "variable"),
    create_time: row_opt_text(r, "create_time"),
    create_user: row_opt_i64(r, "create_user"),
    update_time: row_opt_text(r, "update_time"),
    update_user: row_opt_i64(r, "update_user"),
    is_deleted: row_opt_int(r, "is_deleted"),
  }
}
