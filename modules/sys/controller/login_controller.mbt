// 登录/注销控制器 —— 对齐 mldong 框架约定：登录在 sys 模块（boot2 SysLoginController 同位）。
// 密文校验对齐 boot2：md5(密码明文 + 盐) 小写 hex（core/password.mbt）；
// login_id = sys_user.id 字符串（对齐 boot2 登录 loginId 口径），
// 锁定/删除用户拒绝登录。
// 会话级属性走 moon-token extra（appCode/ip/ua，moon-token 0.1.9 起）——不编进 login_id，
// 免得污染按 login_id 的搜索面；boot2 LoginUser 三件套同物：
// appCode=登录头缺省 platform、ip=客户端 IP、ua=原样 User-Agent（boot2 loginBrowser
// 存的就是原样 UA，os 由日志层解析，骨架同口径存原样）。

///|
pub fn[S : @port.TokenStore, P, R : @svc.RbacService] register_login(
  ctx : @mb.ModuleContext,
  auth : @app.TokenAuth[S, P],
  rbac : R,
  /// 验证码开关读链（holder 经模块装配闭包注入，控制器不依赖 holder 类型）
  captcha_flag_of : () -> Bool,
) -> Unit {
  // 登录（豁免面直挂）
  let login_handler : @mb.Handler = async fn(request, responder) {
    let body = @web.json_body(request)
    let user_name = @core.text_or(body, "userName", "")
    let password = @core.text_or(body, "password", "")
    // 图形验证码（MOLE_CAPTCHA_OPEN 开启时启用，salvo/gin 同口径：防爆破先于账密校验，
    // 一次性消费 + 10 分钟 TTL；开关关闭时行为与改造前一致）
    if captcha_flag_of() && !verify_captcha(@core.text_or(body, "uuid", ""), @core.text_or(body, "code", "")) {
      fail_auth(responder, @core.MldongError::Business("验证码错误或已过期"))
      return
    }
    // appCode：登录头（mldong 框架 APP_CODE_KEY="appCode"），缺省 platform
    let app_code = match request.headers.get("appCode") {
      Some(v) => if v.is_empty() { "platform" } else { v.to_owned() }
      None => "platform"
    }
    // 会话属性：appCode + 登录 ip + 原样 UA（boot2 toLoginUser 三件套同物）
    let kvs : Array[(String, String)] = [("appCode", app_code)]
    match request.ip() {
      Some(ip) => kvs.push(("ip", ip.to_owned()))
      None => ()
    }
    match request.headers.get("User-Agent") {
      Some(ua) => kvs.push(("ua", ua.to_owned()))
      None => ()
    }
    // 凭证编排收口 auth_service（存在性/锁定/密文校验 + 签会话）；
    // 失败统一走 fail_auth 99990401 信封（错密与不存在同话术防枚举）
    let result = @svc.login_by_password(auth, rbac, user_name, password, kvs) catch {
      err => {
        fail_auth(responder, err)
        return
      }
    }
    let data : Json = {
      "token": result.token,
      "refreshToken": result.refresh_token,
      // 契约字段名 userId（对齐 mldong 框架约定 LoginVO；值 = login_id = sys_user.id 字符串）
      "userId": result.login_id,
    }
    responder.send_json(@core.ok_data(data), headers=[("Content-Type", "application/json; charset=utf-8")]) catch {
      _ => ()
    }
  }
  // 刷新 token（UC-0113 全量轮转，公开端点）：旧 access + 旧 refresh 同时失效，返回全新对；
  // 轮转延续会话属性（extra 的 appCode/ip/ua 随转，moon-token rotate 内建）
  let refresh_handler : @mb.Handler = async fn(request, responder) {
    let body = @web.json_body(request)
    let refresh_token = @core.text_or(body, "refreshToken", "")
    let result = auth.rotate(refresh_token) catch {
      _ => {
        // 契约统一业务码 99990410（不存在/已过期/已轮转/已登出，含重放），不泄露具体原因（mldong 框架同口径）
        responder.send_json(
          @core.fail(99990410, "refreshToken无效或已过期"),
          headers=[("Content-Type", "application/json; charset=utf-8")],
        ) catch {
          _ => ()
        }
        return
      }
    }
    let data : Json = {
      "token": result.token,
      "refreshToken": result.refresh_token,
      "userId": result.login_id,
    }
    responder.send_json(@core.ok_data(data), headers=[("Content-Type", "application/json; charset=utf-8")]) catch {
      _ => ()
    }
  }
  // 注销（豁免面直挂；token 自取，剥 Bearer 前缀）
  let logout_handler : @mb.Handler = async fn(request, responder) {
    auth.logout(@web.token_of(request)) catch {
      err => {
        responder.send_json(
          @core.fail(99990401, err.message()),
          headers=[("Content-Type", "application/json; charset=utf-8")],
        ) catch {
          _ => ()
        }
        return
      }
    }
    responder.send_json(@core.ok_empty(), headers=[("Content-Type", "application/json; charset=utf-8")]) catch {
      _ => ()
    }
  }
  // 验证码开关（公开端点，boot2 AuthController 同位）：data.flag 布尔，
  // 开关真值走 holder 读链（env 优先 → sys_config 表 → 默认 false）
  let captcha_flag_handler : @mb.Handler = async fn(_request, responder) {
    responder.send_json(
      @core.ok_data({ "flag": captcha_flag_of() }),
      headers=[("Content-Type", "application/json; charset=utf-8")],
    ) catch {
      _ => ()
    }
  }
  ctx.post("/sys/login", login_handler) catch {
    _ => abort("登录路由注册失败（路由冲突?）")
  }
  ctx.post("/sys/logout", logout_handler) catch {
    _ => abort("注销路由注册失败（路由冲突?）")
  }
  ctx.post("/sys/refreshToken", refresh_handler) catch {
    _ => abort("刷新路由注册失败（路由冲突?）")
  }
  ctx.post("/sys/getCaptchaOpenFlag", captcha_flag_handler) catch {
    _ => abort("验证码开关路由注册失败（路由冲突?）")
  }
}

///|
/// 鉴权失败统一出信封（HTTP 恒 200，boot2 GlobalExceptionHandler 同约定——业务码在 body）
async fn fail_auth(responder : @mb.Responder, e : @core.MldongError) -> Unit {
  responder.send_json(
    { "code": 99990401, "msg": e.message(), "data": Json::null() },
    headers=[("Content-Type", "application/json; charset=utf-8")],
  ) catch {
    _ => ()
  }
}
