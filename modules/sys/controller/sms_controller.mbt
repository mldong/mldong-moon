// sms 发送面 —— boot2 SmsController 同位四端点：
//   POST /sys/sms/sendCode           免登录  {phone,bizType} → {taskId}
//   POST /sys/sms/verifyCode         免登录  {phone,bizType,code} → bool
//   POST /sys/sms/sendNotification   sys:sms:sendNotification  {phone,bizType,params} → {success,taskId,messageId}
//   POST /sys/sms/batchSendNotification sys:sms:batchSendNotification {phones,bizType,params} → [{phone,success,...}]
// 发送通道 mock（moon 无短信 SDK 依赖）：验证码内存态（phone:bizType 键，TTL 5 分钟，
// 一次性消费），通知按 sys_sms_template.biz_type 取模板渲染 {k} 占位后落 sys_sms_log。
// 模板未配置时降级通用文案，发送恒 success——真通道接入属后续轮（差异记 base-contract §4）。

///|
priv struct SmsCodeItem {
  code : String
  expire_at : Int64
}

///|
let sms_code_store : Map[String, SmsCodeItem] = Map([], capacity=0)

///|
/// Json 顶层键取（Object 之外恒 None）
fn json_get(body : Json, key : String) -> Json? {
  match body {
    Object(map) => map.get(key)
    _ => None
  }
}

///|
/// 渲染模板：{k} 占位替换（未命中的键原样保留）
fn render_sms_content(tpl : String, params : Map[String, String]) -> String {
  let mut out = tpl
  for kv in params {
    out = out.replace(old="{\{kv.0}}", new=kv.1)
  }
  out
}

///|
/// 验证码发送 + 通知发送（模板渲染）共用落日志路；返回 taskId 字符串
async fn[L : @svc.SmsLogService] sms_send_log(
  smslog : L,
  ctx : @core.Ctx,
  phone : String,
  biz_type : Int,
  content : String,
  status : Int,
  error_msg : String?,
) -> String raise @core.MldongError {
  let task_id = @core.next_id()
  let req : @dto.SmsLogSaveReq = {
    id: 0L,
    task_id: Some(task_id),
    phone,
    biz_type,
    provider: Some("mock"),
    content: Some(content),
    status: Some(status),
    error_msg,
    cost_ms: Some(0),
    client_ip: None,
  }
  let _ = smslog.save(ctx, req)
  task_id.to_string()
}

///|
pub fn[
  S : @port.TokenStore,
  P : @port.PermissionProvider,
  L : @svc.SmsLogService,
  D : @dao.SmsTemplateDao,
] register_sms(
  ctx : @mb.ModuleContext,
  smslog : L,
  tpl_dao : D,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let send_code_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let phone = @core.text_or(body, "phone", "")
    let biz_type = @core.get_int(body, "bizType").unwrap_or(0)
    if phone.is_empty() || biz_type == 0 {
      raise @core.MldongError::InvalidParam("phone/bizType 不能为空")
    }
    let rand = @random.Rand::new()
    let code = StringBuilder()
    for _ in 0..<6 {
      code.write_char(("0123456789".get_char(rand.int(limit=10)).unwrap_or('0')))
    }
    let code = code.to_string()
    sms_code_store.set(
      "\{phone}:\{biz_type}",
      SmsCodeItem::{ code, expire_at: @core.epoch_millis() + 300_000L },
    )
    let task_id = sms_send_log(smslog, ctx, phone, biz_type, "【mock】验证码：\{code}，5 分钟内有效", 1, None)
    @core.ok_data({ "taskId": task_id })
  })
  let verify_code_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    let phone = @core.text_or(body, "phone", "")
    let biz_type = @core.get_int(body, "bizType").unwrap_or(0)
    let code = @core.text_or(body, "code", "")
    let key = "\{phone}:\{biz_type}"
    let now = @core.epoch_millis()
    // 一次性消费：取出即删；缺失/过期/不匹配均 false（幂等布尔，不抛业务错——boot2 Boolean 同）
    let item = sms_code_store.get(key)
    sms_code_store.remove(key)
    let ok = match item {
      Some(it) => it.expire_at > now && it.code == code
      None => false
    }
    @core.ok_data(Json::boolean(ok))
  })
  // 模板查找：按 biz_type 取启用模板（单行），渲染 {k} 占位；未配置降级通用文案
  let render_notification = async fn(biz_type : Int, params : Map[String, String]) -> String raise @core.MldongError {
    let w = @core.where_()
    let _ = w.eq("biz_type", @core.I(biz_type))
    let (_, rows) = tpl_dao.page(w, 1, 1)
    match rows.get(0) {
      Some(tpl) => if tpl.content.is_empty() {
        "【mock】通知短信（模板内容为空）"
      } else {
        render_sms_content(tpl.content, params)
      }
      None => "【mock】通知短信（未配置模板）"
    }
  }
  let params_of = fn(body : Json) -> Map[String, String] {
    let m : Map[String, String] = Map([], capacity=0)
    match body {
      Object(map) =>
        for kv in map {
          match kv.1 {
            Json::String(s) => m.set(kv.0, s)
            Json::Number(n, ..) => m.set(kv.0, n.to_string())
            _ => ()
          }
        }
      _ => ()
    }
    m
  }
  let send_notification_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let phone = @core.text_or(body, "phone", "")
    let biz_type = @core.get_int(body, "bizType").unwrap_or(0)
    if phone.is_empty() || biz_type == 0 {
      raise @core.MldongError::InvalidParam("phone/bizType 不能为空")
    }
    let content = render_notification(biz_type, params_of(json_get(body, "params").unwrap_or(Json::null())))
    let task_id = sms_send_log(smslog, ctx, phone, biz_type, content, 1, None)
    @core.ok_data({
      "success": Json::boolean(true),
      "taskId": Json::string(task_id),
      "messageId": Json::string(task_id),
    })
  })
  let batch_send_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let biz_type = @core.get_int(body, "bizType").unwrap_or(0)
    if biz_type == 0 {
      raise @core.MldongError::InvalidParam("bizType 不能为空")
    }
    let params = params_of(json_get(body, "params").unwrap_or(Json::null()))
    let content = render_notification(biz_type, params)
    let phones : Array[String] = []
    match json_get(body, "phones").unwrap_or(Json::null()) {
      Json::Array(items) =>
        for it in items {
          match it {
            Json::String(s) => phones.push(s)
            _ => ()
          }
        }
      _ => ()
    }
    if phones.is_empty() {
      raise @core.MldongError::InvalidParam("phones 不能为空")
    }
    let arr : Array[Json] = []
    for phone in phones {
      let task_id = sms_send_log(smslog, ctx, phone, biz_type, content, 1, None)
      arr.push({
        "phone": Json::string(phone),
        "success": Json::boolean(true),
        "taskId": Json::string(task_id),
        "messageId": Json::string(task_id),
      })
    }
    @core.ok_data(Json::array(arr))
  })
  g.post(ctx, "/sys/sms/sendCode", send_code_handler)
  g.post(ctx, "/sys/sms/verifyCode", verify_code_handler)
  g.post(ctx, "/sys/sms/sendNotification", send_notification_handler)
  g.post(ctx, "/sys/sms/batchSendNotification", batch_send_handler)
}

///|
/// sms 权限码片段（sendCode/verifyCode 免登录在 main 豁免面）
pub fn sms_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(
      @guard.RouteRule::make("/sys/sms/sendNotification", ["sys:sms:sendNotification"]),
    )
    .rule(
      @guard.RouteRule::make(
        "/sys/sms/batchSendNotification",
        ["sys:sms:batchSendNotification"],
      ),
    )
}
