// 登录/注销控制器 —— 对齐 13 栈：登录在 sys 模块（boot2 SysLoginController 同位）。
// 骨架不验密码（TODO 接 sys_user 密文校验：password = md5(salt+pwd) 同款规则）；
// login_id = sys_user.id 字符串（对齐 sa-token StpUtil.login(user.getId())），
// 锁定/删除用户拒绝登录。
// 会话级属性走 moon-token extra（appCode/ip/ua，moon-token 0.1.9 起）——不编进 login_id，
// 免得污染按 login_id 的搜索面；boot2 LoginUser 三件套同物：
// appCode=登录头缺省 platform、ip=客户端 IP、ua=原样 User-Agent（boot2 loginBrowser
// 存的就是原样 UA，os 是日志层 hutool 解析的，骨架同口径存原样）。

///|
pub fn[S : @port.TokenStore, P, R : @svc.RbacService] register_login(
  ctx : @mb.ModuleContext,
  auth : @app.TokenAuth[S, P],
  rbac : R,
) -> Unit raise {
  // 登录（豁免面直挂）
  let login_handler : @mb.Handler = async fn(request, responder) {
    let body = @web.json_body(request) catch {
      _ => raise @core.MldongError::InvalidInput("请求体必须是合法 JSON")
    }
    let user_name = @core.text_or(body, "userName", "")
    // 骨架不验密码（TODO 接密文校验）；存在性 + 锁定检查
    let ua = rbac.find_user_auth_by_name(user_name)
    let ua = match ua {
      None => {
        fail_auth(responder, @core.MldongError::Business("用户名或密码错误"))
        return
      }
      Some(ua) => ua
    }
    if ua.is_locked == Some(1) {
      fail_auth(responder, @core.MldongError::Business("用户已锁定"))
      return
    }
    // appCode：登录头（13 栈 APP_CODE_KEY="appCode"），缺省 platform
    let app_code = match request.headers.get("appCode") {
      Some(v) => if v.is_empty() { "platform" } else { v.to_owned() }
      None => "platform"
    }
    // extra 会话属性：appCode + 登录 ip + 原样 UA（boot2 toLoginUser 三件套同物）
    let kvs : Array[(String, String)] = [("appCode", app_code)]
    match request.ip() {
      Some(ip) => kvs.push(("ip", ip.to_owned()))
      None => ()
    }
    match request.headers.get("User-Agent") {
      Some(ua) => kvs.push(("ua", ua.to_owned()))
      None => ()
    }
    let extra : Map[String, String] = Map::from_iter(kvs.iter())
    let result = auth.login(ua.id.to_string(), device="pc", extra=Some(extra)) catch {
      err => {
        fail_auth(responder, @core.MldongError::Internal(err.message()))
        return
      }
    }
    let data : Json = {
      "token": result.token,
      "refreshToken": result.refresh_token,
      "loginId": result.login_id,
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
          status=401,
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
  ctx.post("/sys/login", login_handler) catch {
    _ => abort("登录路由注册失败（路由冲突?）")
  }
  ctx.post("/sys/logout", logout_handler) catch {
    _ => abort("注销路由注册失败（路由冲突?）")
  }
}

///|
/// 鉴权失败统一出 401 + 信封
async fn fail_auth(responder : @mb.Responder, e : @core.MldongError) -> Unit {
  responder.send_json(
    { "code": 99990401, "msg": e.message(), "data": Json::null() },
    status=401,
    headers=[("Content-Type", "application/json; charset=utf-8")],
  ) catch {
    _ => ()
  }
}
