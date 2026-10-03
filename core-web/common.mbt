// 控制层通用工具（moonback 适配）—— 对齐三栈"手写薄端点 + 统一工具"模式
//（boot2 全局异常处理器/CommonResult 与各语言实现的统一错误处理的
//  moonback 对应物；moonback handler 无 raise 通道，wrap 即统一错误转换的唯一落点，源码论证见 hub 选型文档 §6.4.4.1）
//
// 落位规则：所有模块（sys/dev/biz）的 controller 统一 import 本模块，web 依赖（moonback）
// 在依赖图上只出现在 core-web 与各模块 controller 两处；core 保持零 web。

///|
/// handler 统一包装：业务闭包（只许抛 MldongError）正常返回透传、错误转 9999xxxx 信封
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
