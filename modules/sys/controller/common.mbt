// 控制层通用工具 —— 对齐三栈"手写薄端点 + 统一工具"模式（boot2 全局异常处理器/CommonResult、
// goframe ErrorHandlerMiddleware、fastapi exception_handler 的 moonback 对应物）：
//   wrap = 错误统一转换（moonback handler 无 raise 通道，高阶包装即全局异常处理的落点）
//   json_body = 请求体统一解析（非法 JSON → 99990001）
// 响应规则工具在 core（ok_empty/ok_data/ok_page/fail），controller 显式调用（boot2 CommonResult 同款）；
// 入参校验在 dto（moon_zod），校验失败抛 InvalidInput 经 wrap 统一转码。
// 端点本身手写——不做路由参数化（owner 10-03 定：CrudHandlers/register_crud 方向不采纳）。

///|
/// handler 统一包装：业务闭包（只许抛 MldongError）正常返回透传、错误转信封
pub fn wrap(handle_body : async (@mb.Request) -> Json raise @core.MldongError) -> @mb.Handler {
  async fn(request, responder) {
    let body : Json = handle_body(request) catch {
      err => @core.fail_of(err)
    }
    responder.send_json(body, headers=[("Content-Type", "application/json; charset=utf-8")]) catch {
      _ => ()
    }
  }
}

///|
/// 读 JSON 请求体（非法 → 99990001）
pub async fn json_body(request : @mb.Request) -> Json raise @core.MldongError {
  request.body.json() catch {
    _ => raise @core.MldongError::InvalidInput("请求体必须是合法 JSON")
  }
}
