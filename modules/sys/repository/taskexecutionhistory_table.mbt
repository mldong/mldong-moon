// sys_task_execution_history 表编解码器 —— BaseDao 模板的每实体配置〔cmd/gen 生成，可手改〕

///|
let taskexecutionhistory_table : TableCodec[@entity.TaskExecutionHistory] = TableCodec::{
  name: "sys_task_execution_history",
  cols: [
    "id",
    "task_name",
    "spring_bean_name",
    "biz_id",
    "task_state",
    "finished_time",
    "allow_max_error_count",
    "error_count",
    "error_reason",
    "variable",
    "create_time",
    "create_user",
    "update_time",
    "update_user",
  ],
  insert_cols: [
    { name: "id", get: fn(d) { L(d.id) } },
    { name: "task_name", get: fn(d) { S(d.task_name) } },
    { name: "spring_bean_name", get: fn(d) { S(d.spring_bean_name) } },
    { name: "biz_id", get: fn(d) { L(d.biz_id) } },
    { name: "task_state", get: fn(d) { opt_i(d.task_state) } },
    { name: "finished_time", get: fn(d) { opt_s(d.finished_time) } },
    { name: "allow_max_error_count", get: fn(d) { opt_i(d.allow_max_error_count) } },
    { name: "error_count", get: fn(d) { opt_i(d.error_count) } },
    { name: "error_reason", get: fn(d) { opt_s(d.error_reason) } },
    { name: "variable", get: fn(d) { opt_s(d.variable) } },
    { name: "create_time", get: fn(d) { S(match d.create_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "update_time", get: fn(d) { S(match d.update_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "create_user", get: fn(d) { opt_l(d.create_user) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  update_cols: [
    { name: "task_name", get: fn(d) { S(d.task_name) } },
    { name: "spring_bean_name", get: fn(d) { S(d.spring_bean_name) } },
    { name: "biz_id", get: fn(d) { L(d.biz_id) } },
    { name: "task_state", get: fn(d) { opt_i(d.task_state) } },
    { name: "finished_time", get: fn(d) { opt_s(d.finished_time) } },
    { name: "allow_max_error_count", get: fn(d) { opt_i(d.allow_max_error_count) } },
    { name: "error_count", get: fn(d) { opt_i(d.error_count) } },
    { name: "error_reason", get: fn(d) { opt_s(d.error_reason) } },
    { name: "variable", get: fn(d) { opt_s(d.variable) } },
    { name: "update_time", get: fn(_d) { S(@core.now_str()) } },
    { name: "update_user", get: fn(d) { opt_l(d.update_user) } },
  ],
  from_row: row_taskexecutionhistory,
  id_of: fn(d) { L(d.id) },
  del_col: None,
  order_col: "create_time",
}

///|
/// 行映射按列名取 —— 手写行映射（无反射）
fn row_taskexecutionhistory(r : @moondb.Row) -> @entity.TaskExecutionHistory {
  {
    id: row_i64(r, "id"),
    task_name: row_text(r, "task_name", ""),
    spring_bean_name: row_text(r, "spring_bean_name", ""),
    biz_id: row_i64(r, "biz_id"),
    task_state: row_opt_int(r, "task_state"),
    finished_time: row_opt_text(r, "finished_time"),
    allow_max_error_count: row_opt_int(r, "allow_max_error_count"),
    error_count: row_opt_int(r, "error_count"),
    error_reason: row_opt_text(r, "error_reason"),
    variable: row_opt_text(r, "variable"),
    create_time: row_opt_text(r, "create_time"),
    create_user: row_opt_i64(r, "create_user"),
    update_time: row_opt_text(r, "update_time"),
    update_user: row_opt_i64(r, "update_user"),
  }
}
