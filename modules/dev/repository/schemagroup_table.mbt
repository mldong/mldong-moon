// dev_schema_group 表编解码器 —— BaseDao 模板的每实体配置〔cmd/gen 生成，可手改〕

///|
let schemagroup_table : TableCodec[@entity.SchemaGroup] = TableCodec::{
  name: "dev_schema_group",
  cols: [
    "id",
    "name",
    "code",
    "icon",
    "sort",
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
    { name: "name", get: fn(d) { S(d.name) } },
    { name: "code", get: fn(d) { S(d.code) } },
    { name: "icon", get: fn(d) { opt_s(d.icon) } },
    { name: "sort", get: fn(d) { opt_l(d.sort) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "variable", get: fn(d) { opt_s(d.variable) } },
    { name: "create_time", get: fn(d) { S(match d.create_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "update_time", get: fn(d) { S(match d.update_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "create_user", get: fn(d) { opt_l(d.create_user) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  update_cols: [
    { name: "name", get: fn(d) { S(d.name) } },
    { name: "code", get: fn(d) { S(d.code) } },
    { name: "icon", get: fn(d) { opt_s(d.icon) } },
    { name: "sort", get: fn(d) { opt_l(d.sort) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "variable", get: fn(d) { opt_s(d.variable) } },
    { name: "update_time", get: fn(_d) { S(@core.now_str()) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  from_row: row_schemagroup,
  id_of: fn(d) { L(d.id) },
  del_col: Some("is_deleted"),
  order_col: "create_time",
}

///|
/// 行映射按列名取 —— MyBatis resultMap 的手写对应物
fn row_schemagroup(r : @moondb.Row) -> @entity.SchemaGroup {
  {
    id: row_i64(r, "id"),
    name: row_text(r, "name", ""),
    code: row_text(r, "code", ""),
    icon: row_opt_text(r, "icon"),
    sort: row_opt_i64(r, "sort"),
    remark: row_opt_text(r, "remark"),
    variable: row_opt_text(r, "variable"),
    create_time: row_opt_text(r, "create_time"),
    create_user: row_opt_i64(r, "create_user"),
    update_time: row_opt_text(r, "update_time"),
    update_user: row_opt_i64(r, "update_user"),
    is_deleted: row_opt_int(r, "is_deleted"),
  }
}
