// sys_user 入参契约 —— schema + parse + Req（moon_zod 全工程唯一入口）；出参装配同层

///|
/// save/update 共用（update 要求 id > 0，parse_update 里校验）
pub(all) struct UserSaveReq {
  mut id : Int64
  user_name : String
  real_name : String
  nick_name : String?
  mobile_phone : String?
  tel : String?
  email : String?
  sex : Int?
  dept_id : Int64?
  remark : String?
}

///|
let save_schema : @moon_zod.Schema = @moon_zod.object({
  // id/deptId 是雪花（数字或字符串都可能来），不参与校验但要在 strip 模式下存活
  "id": @moon_zod.any().optional(),
  "deptId": @moon_zod.any().optional(),
  "userName": @moon_zod.string().min(2, msg="用户名至少 2 个字符").max(32),
  "realName": @moon_zod.string().min(1, msg="姓名不能为空").max(32),
  "nickName": @moon_zod.string().max(32, msg="昵称最多 32 位").optional(),
  "mobilePhone": @moon_zod.string().max(11, msg="手机号最多 11 位").optional(),
  "tel": @moon_zod.string().max(20, msg="联系电话最多 20 位").optional(),
  "email": @moon_zod.string().max(32, msg="邮箱最多 32 位").optional(),
  "sex": @moon_zod.number().int().optional(),
  "remark": @moon_zod.string().max(255, msg="备注最多 255 位").optional(),
})

///|
/// 从 Json 提取 Req
fn req_of(data : Json) -> UserSaveReq {
  {
    id: @core.get_i64(data, "id").unwrap_or(0L),
    user_name: @core.text_or(data, "userName", ""),
    real_name: @core.text_or(data, "realName", ""),
    nick_name: @core.get_text(data, "nickName"),
    mobile_phone: @core.get_text(data, "mobilePhone"),
    tel: @core.get_text(data, "tel"),
    email: @core.get_text(data, "email"),
    sex: @core.get_int(data, "sex"),
    dept_id: @core.get_i64(data, "deptId"),
    remark: @core.get_text(data, "remark"),
  }
}

///|
pub fn parse_save(body : Json) -> UserSaveReq raise @core.MldongError {
  match save_schema.parse(body) {
    Ok(data) => req_of(data)
    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())
  }
}

///|
pub fn parse_update(body : Json) -> UserSaveReq raise @core.MldongError {
  let req = parse_save(body)
  if req.id <= 0L {
    raise @core.MldongError::InvalidInput("用户ID不能为空")
  }
  req
}

///|
/// 分页入参：m_* 动态条件统一由 core 通用查询件解析（13 栈同约定），
/// 关键字走 keywords+searchKeys（多列 OR）
pub(all) struct UserPageReq {
  page_num : Int
  page_size : Int
  /// m_ 参数解析出的动态条件（13 个操作符 + 表别名 4 段式）
  m : @core.Wrapper
  /// keywords/searchKeys 原文（关键字搜索由 service 按列白名单应用）
  keywords : String
  search_keys : String
}

///|
pub fn parse_page(body : Json) -> UserPageReq raise @core.MldongError {
  let page_num = @core.get_int(body, "pageNum").unwrap_or(1)
  let page_size = @core.get_int(body, "pageSize").unwrap_or(10)
  if page_num <= 0 || page_size <= 0 || page_size > 200 {
    raise @core.MldongError::InvalidInput("分页参数非法")
  }
  {
    page_num,
    page_size,
    m: @core.parse_m_params(body, exclude=["pageNum", "pageSize", "keywords", "searchKeys"]),
    keywords: @core.text_or(body, "keywords", ""),
    search_keys: @core.text_or(body, "searchKeys", ""),
  }
}

///|
/// 出参装配：User → Json（camelCase，对齐 boot2 UserVO 字段；dept/role join 后续加）
pub fn user_json(u : @entity.User) -> Json {
  {
    "id": u.id.to_string(),
    "userName": u.user_name,
    "realName": u.real_name,
    "nickName": jstr(u.nick_name),
    "mobilePhone": jstr(u.mobile_phone),
    "tel": jstr(u.tel),
    "email": jstr(u.email),
    "sex": jint(u.sex),
    "adminType": jint(u.admin_type),
    "isLocked": jint(u.is_locked),
    "deptId": jsnow(u.dept_id),
    "remark": jstr(u.remark),
    "createTime": jstr(u.create_time),
    "updateTime": jstr(u.update_time),
    "isDeleted": jint(u.is_deleted),
  }
}

///|
/// 关联行出参：user 全字段 + dept/post 名称编码（对齐 boot2 UserVO 形状）
pub fn page_row_json(row : @entity.UserPageRow) -> Json {
  let u = row.user
  {
    "id": u.id.to_string(),
    "userName": u.user_name,
    "realName": u.real_name,
    "nickName": jstr(u.nick_name),
    "mobilePhone": jstr(u.mobile_phone),
    "tel": jstr(u.tel),
    "email": jstr(u.email),
    "sex": jint(u.sex),
    "adminType": jint(u.admin_type),
    "isLocked": jint(u.is_locked),
    "deptId": jsnow(u.dept_id),
    "deptName": jstr(row.dept_name),
    "deptCode": jstr(row.dept_code),
    "postName": jstr(row.post_name),
    "postCode": jstr(row.post_code),
    "remark": jstr(u.remark),
    "createTime": jstr(u.create_time),
    "updateTime": jstr(u.update_time),
  }
}

///|
fn jstr(v : String?) -> Json {
  match v {
    Some(s) => Json::string(s)
    None => Json::null()
  }
}

///|
fn jint(v : Int?) -> Json {
  match v {
    Some(n) => Json::number(n.to_double())
    None => Json::null()
  }
}

///|
/// 雪花 id 一律字符串化（JS Number 53 位精度装不下 64 位雪花，13 栈同坑同修）
fn jsnow(v : Int64?) -> Json {
  match v {
    Some(n) => Json::string(n.to_string())
    None => Json::null()
  }
}
