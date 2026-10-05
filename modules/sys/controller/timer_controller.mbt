// timer 定时任务面 —— boot2 TimerController 同位（内存态，无表；boot2 TimerCache 同物）。
// moon 无 cron 调度器与 runner bean，页面数据存进程内存：
//   save/remove 为 moon 补面（前端 timer.ts 有调用；boot2 未暴露 save/remove）
//   stop/start 共用 sys:timer:stop 码（boot2 同）、update {id|name,remark,redisCron}、
//   detail/page/reset/executeImmediate 同 boot2 语义
//   state：1=运行 2=停止（boot4 TimerStateEnum 同码）
// 内存态重启即失——boot2 数据本就源自 runner bean 注册，语义对齐。

///|
priv struct TimerItem {
  id : String
  timer_name : String
  action_class : String
  cron : String
  mut redis_cron : String
  mut state : Int
  mut remark : String
}

///|
let timer_store : Map[String, TimerItem] = Map([], capacity=0)

///|
/// TimerModel JSON（boot2 TimerModel 同字段；id 字符串）
fn timer_json(t : TimerItem) -> Json {
  {
    "id": Json::string(t.id),
    "timerName": Json::string(t.timer_name),
    "actionClass": Json::string(t.action_class),
    "cron": Json::string(t.cron),
    "redisCron": Json::string(t.redis_cron),
    "state": Json::number(t.state.to_double()),
    "remark": Json::string(t.remark),
  }
}

///|
/// id|name 双键取（boot2 param.get("id",param.getStr("name")) 同语义）
fn timer_find(body : Json) -> TimerItem? {
  let id = @core.text_or(body, "id", "")
  let name = if id.is_empty() { @core.text_or(body, "name", "") } else { id }
  if !id.is_empty() {
    match timer_store.get(id) {
      Some(t) => return Some(t)
      None => ()
    }
  }
  if !name.is_empty() {
    for kv in timer_store {
      if kv.1.timer_name == name {
        return Some(kv.1)
      }
    }
  }
  None
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] register_timer(
  ctx : @mb.ModuleContext,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    let timer_name = @core.text_or(body, "timerName", "")
    if timer_name.is_empty() {
      raise @core.MldongError::InvalidParam("timerName 不能为空")
    }
    for kv in timer_store {
      if kv.1.timer_name == timer_name {
        raise @core.MldongError::Business("任务名已存在: " + timer_name)
      }
    }
    let id = @core.next_id().to_string()
    let cron = @core.text_or(body, "cron", "")
    timer_store.set(
      id,
      TimerItem::{
        id,
        timer_name,
        action_class: @core.text_or(body, "actionClass", ""),
        cron,
        redis_cron: if cron.is_empty() { @core.text_or(body, "redisCron", "") } else { cron },
        state: 2,
        remark: @core.text_or(body, "remark", ""),
      },
    )
    @core.ok_data(Json::string(id))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ids = @core.get_text_array(@web.json_body(request), "ids")
    for id in ids {
      timer_store.remove(id)
    }
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    match timer_find(@web.json_body(request)) {
      Some(t) => @core.ok_data(timer_json(t))
      None => raise @core.MldongError::NotFound("任务不存在")
    }
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    let page_num = @core.get_int(body, "pageNum").unwrap_or(1)
    let page_size = @core.get_int(body, "pageSize").unwrap_or(10)
    let keywords = @core.text_or(body, "keywords", "").to_lower()
    let mut all : Array[TimerItem] = []
    for kv in timer_store {
      all.push(kv.1)
    }
    if !keywords.is_empty() {
      all = all.filter(fn(t) { t.timer_name.to_lower().contains(keywords) || t.action_class.to_lower().contains(keywords) })
    }
    let total = all.length()
    let start = (page_num - 1) * page_size
    let rows : Array[Json] = []
    for i in 0..<page_size {
      let idx = start + i
      if idx < total {
        rows.push(timer_json(all[idx]))
      }
    }
    @core.ok_page(page_num, page_size, total, rows)
  })
  // stop/start 同码 sys:timer:stop（boot2 注解同款）；moon 无调度器，state 翻转即语义
  let stop_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    match timer_find(@web.json_body(request)) {
      Some(t) => {
        t.state = 2
        @core.ok_empty()
      }
      None => @core.ok_empty()
    }
  })
  let start_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    match timer_find(@web.json_body(request)) {
      Some(t) => {
        t.state = 1
        @core.ok_empty()
      }
      None => @core.ok_empty()
    }
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    match timer_find(body) {
      Some(t) => {
        let remark = @core.text_or(body, "remark", "")
        let redis_cron = @core.text_or(body, "redisCron", "")
        if !remark.is_empty() {
          t.remark = remark
        }
        if !redis_cron.is_empty() {
          t.redis_cron = redis_cron
        }
        @core.ok_empty()
      }
      // boot2 update 对未知 id 也是静默 ok（cache 无键不做事）
      None => @core.ok_empty()
    }
  })
  // reset：redisCron 回落声明 cron + 停止（boot2 按 runner 缺省重置同向）
  let reset_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    let ids = @core.get_text_array(body, "ids")
    if ids.is_empty() {
      for kv in timer_store {
        kv.1.redis_cron = kv.1.cron
        kv.1.state = 2
      }
    } else {
      for id in ids {
        match timer_store.get(id) {
          Some(t) => {
            t.redis_cron = t.cron
            t.state = 2
          }
          None => ()
        }
      }
    }
    @core.ok_empty()
  })
  // executeImmediate：moon 无 runner 可执行，幂等 ok（boot2 对存在 runner 才真跑）
  let exec_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let _ = timer_find(@web.json_body(request))
    @core.ok_empty()
  })
  g.post(ctx, "/sys/timer/save", save_handler)
  g.post(ctx, "/sys/timer/remove", remove_handler)
  g.post(ctx, "/sys/timer/detail", detail_handler)
  g.post(ctx, "/sys/timer/page", page_handler)
  g.post(ctx, "/sys/timer/stop", stop_handler)
  g.post(ctx, "/sys/timer/start", start_handler)
  g.post(ctx, "/sys/timer/update", update_handler)
  g.post(ctx, "/sys/timer/reset", reset_handler)
  g.post(ctx, "/sys/timer/executeImmediate", exec_handler)
}

///|
/// timer 权限码片段（stop/start 双端点共用 sys:timer:stop——boot2 注解同款）
pub fn timer_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/timer/save", ["sys:timer:save"]))
    .rule(@guard.RouteRule::make("/sys/timer/remove", ["sys:timer:remove"]))
    .rule(@guard.RouteRule::make("/sys/timer/detail", ["sys:timer:detail"]))
    .rule(@guard.RouteRule::make("/sys/timer/page", ["sys:timer:page"]))
    .rule(@guard.RouteRule::make("/sys/timer/stop", ["sys:timer:stop"]))
    .rule(@guard.RouteRule::make("/sys/timer/start", ["sys:timer:stop"]))
    .rule(@guard.RouteRule::make("/sys/timer/update", ["sys:timer:update"]))
    .rule(@guard.RouteRule::make("/sys/timer/reset", ["sys:timer:reset"]))
    .rule(
      @guard.RouteRule::make("/sys/timer/executeImmediate", ["sys:timer:executeImmediate"]),
    )
}
