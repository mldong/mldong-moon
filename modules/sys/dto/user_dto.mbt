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
    Err(errors) => raise @core.MldongError::InvalidParam(errors[0].to_string())
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
/// 分页入参：m_* 动态条件统一由 core 通用查询件解析（mldong 框架同约定），
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
  if page_num <= 0 || page_size <= 0 {
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
    "avatar": jstr(u.avatar),
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
    "avatar": jstr(u.avatar),
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
/// 雪花 id 一律字符串化（JS Number 53 位精度装不下 64 位雪花，同款坑统一修）
fn jsnow(v : Int64?) -> Json {
  match v {
    Some(n) => Json::string(n.to_string())
    None => Json::null()
  }
}


///|
/// 在线 token 级行（对齐 boot2 OnlineUserVO 的 tokenList 项）
pub(all) struct OnlineTokenView {
  token_value : String
  is_current : Bool
  /// 登录时刻（epoch ms）
  login_time : Int64
  /// 会话到期时刻（epoch ms）
  expire_at : Int64
  login_ip : String
  login_browser : String
  super_admin : Bool
}

///|
/// 在线用户级行（按登录人分组，boot2 同构：一行一带 tokenList）
pub(all) struct OnlineUserView {
  id : String
  user_name : String
  real_name : String
  is_current : Bool
  super_admin : Bool
  login_time : Int64
  expire_at : Int64
  /// 顶层行级字段（对齐 boot4/goframe：取该用户最新 token 的值；超管他人凭证置 "-"）
  token_value : String
  login_ip : String
  login_browser : String
  tokens : Array[OnlineTokenView]
}

///|
/// epoch ms → "yyyy-MM-dd HH:mm:ss"（UTC；boot2 用服务器时区，骨架先统一 UTC）
fn jms(ms : Int64) -> Json {
  Json::string(@core.format_unix_utc(ms / 1000L))
}

///|
pub fn online_token_json(v : OnlineTokenView) -> Json {
  {
    "tokenValue": v.token_value,
    "isCurrentUser": Json::boolean(v.is_current),
    "loginTime": jms(v.login_time),
    "expireTime": jms(v.expire_at),
    "loginIp": Json::string(v.login_ip),
    "loginBrowser": Json::string(v.login_browser),
    "superAdmin": Json::boolean(v.super_admin),
  }
}

///|
pub fn online_user_json(v : OnlineUserView) -> Json {
  let arr : Array[Json] = []
  for t in v.tokens {
    arr.push(online_token_json(t))
  }
  {
    "id": v.id,
    "userName": v.user_name,
    "realName": v.real_name,
    "superAdmin": Json::boolean(v.super_admin),
    "isCurrentUser": Json::boolean(v.is_current),
    "loginTime": jms(v.login_time),
    "expireTime": jms(v.expire_at),
    // 顶层行级三件（goframe/boot4 契约：超管他人凭证置 "-"）
    "tokenValue": v.token_value,
    "loginIp": v.login_ip,
    "loginBrowser": v.login_browser,
    "tokenList": Json::array(arr),
  }
}


///|
/// 个人信息入参（boot2 ValidInfo 组：realName 必填，nickName/sex 可选；其余字段忽略）
pub fn parse_info(body : Json) -> UserSaveReq raise @core.MldongError {
  let req = req_of(body)
  if req.real_name.is_empty() {
    raise @core.MldongError::InvalidInput("姓名不能为空")
  }
  req
}

///|
/// 个人信息出参（boot2 /sys/user/info → LoginUser 的骨架子集：用户字段 + 角色/超管位；
/// deptName/lastLoginTime 契约键由控制器实时补——boot2 loginHandler.postLogin 同位）
pub fn user_info_json(
  u : @entity.User,
  roles : Array[String],
  super_admin : Bool,
  dept_name : String?,
  last_login_time : String?,
) -> Json {
  let base = match user_json(u) {
    Object(map) => map
    _ => abort("user_json 恒为 Object")
  }
  let role_arr : Array[Json] = []
  for r in roles {
    role_arr.push(Json::string(r))
  }
  let _ = base.set("roleCodes", Json::array(role_arr))
  let _ = base.set("roleNames", Json::array(role_arr))
  let _ = base.set("superAdmin", Json::boolean(super_admin))
  let _ = base.set(
    "deptName",
    match dept_name {
      Some(s) => Json::string(s)
      None => Json::null()
    },
  )
  let _ = base.set(
    "lastLoginTime",
    match last_login_time {
      Some(s) => Json::string(s)
      None => Json::null()
    },
  )
  Json::object(base)
}
