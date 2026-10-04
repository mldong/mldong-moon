// 站内信实时推送面 —— SSE（boot2 SseController 同位：POST /sse/events + text/event-stream，
// 需登录；首帧 data:{userId,type:"init",msg:"初始化连接成功"}；10s 心跳保活对齐
// SseTaskRunner 的定时 test 推送）。moonback Responder::respond 流式写 + flush。

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] register_sse(
  ctx : @mb.ModuleContext,
  g : @mbguard.Guard[S, P],
) -> Unit {
  let sse_handler : @mb.Handler = async fn(request, responder) {
    let sctx = @web.ctx_of(request)
    let user_id = sctx.user_id.unwrap_or(0L)
    // 响应头（text/event-stream + 禁缓存；HTTP 200 由 respond 缺省）
    let w = responder.respond(headers=[
      ("Content-Type", "text/event-stream; charset=utf-8"),
      ("Cache-Control", "no-cache"),
    ])
    // 首帧：init（boot2 SseModel{userId,type:"init",msg} 同形状）
    let init_frame =
      "data: {\"userId\":\{user_id},\"type\":\"init\",\"msg\":\"初始化连接成功\"}\n\n"
    w.write(init_frame)
    w.flush() catch {
      _ => return
    }
    // 心跳环（客户端断开时 flush 抛错退出；SSE 注释行 ": ping" 不触发前端 event）
    let heartbeat = @async.Timer::Timer(10_000)
    while true {
      heartbeat.wait() catch {
        _ => return
      }
      heartbeat.refresh()
      w.write(": ping\n\n")
      w.flush() catch {
        _ => return
      }
    }
  }
  g.post(ctx, "/sse/events", sse_handler) catch {
    _ => abort("sse 路由注册失败（路由冲突?）")
  }
}
