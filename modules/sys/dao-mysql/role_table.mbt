// sys_role 表编解码器 —— BaseDao 模板的每实体配置（gen 生成器将来产出的样板）

///|
/// sys_role 表：逻辑删除 is_deleted、默认排序 sort（boot2 分页排序 d.sort 同源）
let role_table : TableCodec[@entity.Role] = TableCodec::{
  name: "sys_role",
  cols: [
    "id", "app_code", "name", "code", "sort", "role_type", "enabled", "data_scope",
    "remark", "create_time", "update_time", "is_deleted",
  ],
  insert_cols: [
    { name: "id", get: fn(r) { L(r.id) } },
    { name: "app_code", get: fn(r) { opt_s(r.app_code) } },
    { name: "name", get: fn(r) { S(r.name) } },
    { name: "code", get: fn(r) { S(r.code) } },
    { name: "sort", get: fn(r) { opt_l(r.sort) } },
    { name: "role_type", get: fn(r) { opt_i(r.role_type) } },
    { name: "enabled", get: fn(r) { I(r.enabled) } },
    { name: "data_scope", get: fn(r) { opt_i(r.data_scope) } },
    { name: "remark", get: fn(r) { opt_s(r.remark) } },
    { name: "create_time", get: fn(r) { S(match r.create_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "create_user", get: fn(r) { opt_l(r.create_user) } },
    { name: "update_user", get: fn(r) { opt_l(r.update_user) } },
  ],
  update_cols: [
    { name: "app_code", get: fn(r) { opt_s(r.app_code) } },
    { name: "name", get: fn(r) { S(r.name) } },
    { name: "code", get: fn(r) { S(r.code) } },
    { name: "sort", get: fn(r) { opt_l(r.sort) } },
    { name: "role_type", get: fn(r) { opt_i(r.role_type) } },
    { name: "enabled", get: fn(r) { I(r.enabled) } },
    { name: "data_scope", get: fn(r) { opt_i(r.data_scope) } },
    { name: "remark", get: fn(r) { opt_s(r.remark) } },
    { name: "update_time", get: fn(_r) { S(@core.now_str()) } },
    { name: "update_user", get: fn(r) { opt_l(r.update_user) } },
  ],
  from_row: row_role,
  id_of: fn(r) { L(r.id) },
  del_col: Some("is_deleted"),
  order_col: "sort",
}

///|
/// 行映射按列名取（variable/create_user/update_user 骨架不回显）
fn row_role(r : @moondb.Row) -> @entity.Role {
  {
    id: row_i64(r, "id"),
    app_code: row_opt_text(r, "app_code"),
    name: row_text(r, "name", ""),
    code: row_text(r, "code", ""),
    sort: row_opt_i64(r, "sort"),
    role_type: row_opt_int(r, "role_type"),
    enabled: row_int_d(r, "enabled", 1),
    data_scope: row_opt_int(r, "data_scope"),
    remark: row_opt_text(r, "remark"),
    create_time: row_opt_datetime(r, "create_time"),
    update_time: row_opt_datetime(r, "update_time"),
    create_user: row_opt_i64(r, "create_user"),
    update_user: row_opt_i64(r, "update_user"),
    is_deleted: row_opt_int(r, "is_deleted"),
  }
}
