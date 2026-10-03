// sys_dept 表编解码器 —— BaseDao 模板的每实体配置〔cmd/gen 生成，可手改〕

///|
let dept_table : TableCodec[@entity.Dept] = TableCodec::{
  name: "sys_dept",
  cols: [
    "id",
    "parent_id",
    "pids",
    "name",
    "code",
    "sort",
    "enabled",
    "leader_ids",
    "main_leader_id",
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
    { name: "parent_id", get: fn(d) { opt_l(d.parent_id) } },
    { name: "name", get: fn(d) { S(d.name) } },
    { name: "code", get: fn(d) { S(d.code) } },
    { name: "sort", get: fn(d) { opt_l(d.sort) } },
    { name: "enabled", get: fn(d) { opt_i(d.enabled) } },
    { name: "leader_ids", get: fn(d) { opt_s(d.leader_ids) } },
    { name: "main_leader_id", get: fn(d) { opt_l(d.main_leader_id) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "create_time", get: fn(d) { S(match d.create_time { Some(s) => s; None => @core.now_str() }) } },
  ],
  update_cols: [
    { name: "parent_id", get: fn(d) { opt_l(d.parent_id) } },
    { name: "name", get: fn(d) { S(d.name) } },
    { name: "code", get: fn(d) { S(d.code) } },
    { name: "sort", get: fn(d) { opt_l(d.sort) } },
    { name: "enabled", get: fn(d) { opt_i(d.enabled) } },
    { name: "leader_ids", get: fn(d) { opt_s(d.leader_ids) } },
    { name: "main_leader_id", get: fn(d) { opt_l(d.main_leader_id) } },
    { name: "remark", get: fn(d) { opt_s(d.remark) } },
    { name: "update_time", get: fn(_d) { S(@core.now_str()) } },
  ],
  from_row: row_dept,
  id_of: fn(d) { L(d.id) },
  del_col: Some("is_deleted"),
  order_col: "create_time",
}

///|
/// 行映射按列名取 —— MyBatis resultMap 的手写对应物
fn row_dept(r : @moondb.Row) -> @entity.Dept {
  {
    id: row_i64(r, "id"),
    parent_id: row_opt_i64(r, "parent_id"),
    pids: row_opt_text(r, "pids"),
    name: row_text(r, "name", ""),
    code: row_text(r, "code", ""),
    sort: row_opt_i64(r, "sort"),
    enabled: row_opt_int(r, "enabled"),
    leader_ids: row_opt_text(r, "leader_ids"),
    main_leader_id: row_opt_i64(r, "main_leader_id"),
    remark: row_opt_text(r, "remark"),
    variable: row_opt_text(r, "variable"),
    create_time: row_opt_text(r, "create_time"),
    create_user: row_opt_i64(r, "create_user"),
    update_time: row_opt_text(r, "update_time"),
    update_user: row_opt_i64(r, "update_user"),
    is_deleted: row_opt_int(r, "is_deleted"),
  }
}
