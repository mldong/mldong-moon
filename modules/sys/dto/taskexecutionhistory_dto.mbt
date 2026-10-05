// sys_task_execution_history 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct TaskExecutionHistorySaveReq {
  mut id : Int64
  mut task_name : String
  mut spring_bean_name : String
  mut biz_id : Int64
  mut task_state : Int?
  mut finished_time : String?
  mut allow_max_error_count : Int?
  mut error_count : Int?
  mut error_reason : String?
  mut variable : String?
}

///|
let taskexecutionhistory_save_schema : @moon_zod.Schema = @moon_zod.object({
  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活
  "id": @moon_zod.any().optional(),
  "taskName": @moon_zod.string().max(100, msg="taskName 最多 100 位"),
  "springBeanName": @moon_zod.string().max(100, msg="springBeanName 最多 100 位"),
  "bizId": @moon_zod.any().optional(),
  "taskState": @moon_zod.number().int().optional(),
  "finishedTime": @moon_zod.string().optional(),
  "allowMaxErrorCount": @moon_zod.number().int().optional(),
  "errorCount": @moon_zod.number().int().optional(),
  "errorReason": @moon_zod.string().optional(),
  "ext": @moon_zod.any().optional(),
})

///|
/// 从 Json 提取 Req
fn taskexecutionhistory_req_of(data : Json) -> TaskExecutionHistorySaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    task_name: @core.text_or(data, "taskName", ""),
    spring_bean_name: @core.text_or(data, "springBeanName", ""),
    biz_id: @core.get_i64(data, "bizId").unwrap_or(0L),
    task_state: @core.get_int(data, "taskState"),
    finished_time: @core.get_text(data, "finishedTime"),
    allow_max_error_count: @core.get_int(data, "allowMaxErrorCount"),
    error_count: @core.get_int(data, "errorCount"),
    error_reason: @core.get_text(data, "errorReason"),
    variable: Some(match @core.get_ext_string(data, "ext") {
      Some(s) => s
      None => "{}"
    }),
  }
}

///|
pub fn taskexecutionhistory_parse_save(body : Json) -> TaskExecutionHistorySaveReq raise @core.MldongError {
  match taskexecutionhistory_save_schema.parse(body) {
    Ok(data) => taskexecutionhistory_req_of(data)
    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())
  }
}

///|
pub fn taskexecutionhistory_parse_update(body : Json) -> TaskExecutionHistorySaveReq raise @core.MldongError {
  let req = taskexecutionhistory_parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("TaskExecutionHistoryID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用
pub(all) struct TaskExecutionHistoryPageReq {
  page_num : Int
  page_size : Int
  m : @core.Wrapper
  keywords : String
  search_keys : String
}

///|
pub fn taskexecutionhistory_parse_page(body : Json) -> TaskExecutionHistoryPageReq raise @core.MldongError {
  let page_num = @core.get_int(body, "pageNum").unwrap_or(1)
  let page_size = @core.get_int(body, "pageSize").unwrap_or(10)
  if page_num <= 0 || page_size <= 0 || page_size > 200 {
    raise @core.MldongError::InvalidInput("分页参数非法")
  }
  {
    page_num,
    page_size,
    m: @core.parse_m_params(body, exclude=["pageNum", "pageSize", "keywords", "searchKeys", "orderBy"]),
    keywords: @core.text_or(body, "keywords", ""),
    search_keys: @core.text_or(body, "searchKeys", ""),
  }
}

///|
/// 出参装配：<Cls> → Json（camelCase；雪花 id 一律字符串化防 JS 精度丢失）
pub fn taskexecutionhistory_json(d : @entity.TaskExecutionHistory) -> Json {
  let obj : Json = {
    "id": d.id.to_string(),
    "taskName": Json::string(d.task_name),
    "springBeanName": Json::string(d.spring_bean_name),
    "bizId": d.biz_id.to_string(),
    "taskState": jint(d.task_state),
    "finishedTime": jstr(d.finished_time),
    "allowMaxErrorCount": jint(d.allow_max_error_count),
    "errorCount": jint(d.error_count),
    "errorReason": jstr(d.error_reason),
    "createTime": jstr(d.create_time),
    "createUser": jsnow(d.create_user),
    "updateTime": jstr(d.update_time),
    "updateUser": jsnow(d.update_user),
  }
  let base = match obj {
    Object(map) => map
    _ => abort("taskexecutionhistory_json 恒为 Object")
  }
  // ext 空不出键（UC-0426：'{}' 恒重写与 NULL 两态同判）
  match @core.ext_json_opt(d.variable) {
    Some(e) => { let _ = base.set("ext", e) }
    None => ()
  }
  Json::object(base)
}
