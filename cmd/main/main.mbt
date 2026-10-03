// mldong-moon 装配入口 —— 鉴权（moon-token）+ 模块自注册（每模块一行）
// 起法：export MLDONG_DB_PWD=... && moon run --target wasm cmd/main   （默认 127.0.0.1:18680）
//
// ⚠ TokenAuth 必须在 main 内构造（不能顶层 let）：wasm 档顶层 let 在 __moonbit_init 阶段
//   求值，那时平台熵未装好，opaque_style() 当场 abort（hub moonback 复测报告 §12 实测）。

///|
/// 权限供数方 —— 骨架内存版（对齐 moon-token demo 形状）：
/// superAdmin 走超管通道（不靠码表）；admin 给 sys:user:*/sys:role:* 全套码；其余登录仅登录态。
/// TODO 接 sys_user_role/sys_role/sys_menu 表后替换（码的真实来源是菜单表）。
struct SkeletonPerms {}

///|
pub impl @port.PermissionProvider for SkeletonPerms with fn get_permissions(
  _self,
  login_id,
  _device,
) {
  if login_id == "admin" {
    [
      "sys:user:save", "sys:user:remove", "sys:user:update", "sys:user:detail", "sys:user:page",
      "sys:role:save", "sys:role:remove", "sys:role:update", "sys:role:detail", "sys:role:page",
    ]
  } else {
    []
  }
}

///|
pub impl @port.PermissionProvider for SkeletonPerms with fn get_roles(_self, login_id, _device) {
  if login_id == "admin" {
    ["admin"]
  } else {
    []
  }
}

///|
pub impl @port.PermissionProvider for SkeletonPerms with fn is_super_admin(_self, login_id, _device) {
  login_id == "superAdmin"
}

///|
/// 从请求取 token（头优先、同名 cookie 兜底；注销端点在豁免面用）。
/// 剥 "Bearer " 前缀——与 TokenConfig.token_prefix 同一约定（豁免面不走 guard 的
/// extract_token，这里必须自己对齐，否则注销拿到的是带前缀的串、查不到会话）。
fn token_of(request : @mb.Request) -> String {
  let raw = match request.headers.get("Authorization") {
    None => ""
    Some(v) => v.to_owned()
  }
  let from_header = if raw.has_prefix("Bearer ") {
    raw.substring(start=7)
  } else {
    raw
  }
  if from_header.is_empty() {
    match request.cookie().get("Authorization") {
      None => ""
      Some(v) => v
    }
  } else {
    from_header
  }
}

///|
async fn main raise {
  let config = @core.MysqlConfig::from_env()
  // 鉴权装配（熵依赖运行时，必须在 main 内构造）
  // token_prefix="Bearer"：对齐 13 栈契约（sa-token token-prefix + vben5 发 "Bearer <token>"）
  let token_cfg = @app.TokenConfig::default()
  token_cfg.token_prefix = "Bearer"
  let auth = @app.TokenAuth::new(
    "user",
    token_cfg,
    @mem.MemoryStore::new("user"),
    SkeletonPerms::{},
    @style.opaque_style(),
  )
  // 总策略 = 全局豁免面（登录/注销）+ 各模块 policy 片段聚合
  let policy = @web.merge_policy(
    @guard.RoutePolicy::new().exempt("/sys/login").exempt("/sys/logout"),
    @sys.policy(),
  )
  let g = @mbguard.Guard::new(auth, policy).with_on_error(@web.on_error)

  let login : @mb.Handler = async fn(request, responder) {
    // 骨架不验密码（TODO 接 sys_user 密文校验后替换）；userName 即登录身份
    let body = @web.json_body(request) catch {
      _ => { "userName": "" }
    }
    let user_name = @core.text_or(body, "userName", "")
    let result = auth.login(user_name, device="pc") catch {
      err => {
        responder.send_json(@core.fail(99990401, err.message()), status=401, headers=[("Content-Type", "application/json; charset=utf-8")]) catch {
          _ => ()
        }
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
  let logout : @mb.Handler = async fn(request, responder) {
    auth.logout(token_of(request)) catch {
      err => {
        responder.send_json(@core.fail(99990401, err.message()), status=401, headers=[("Content-Type", "application/json; charset=utf-8")]) catch {
          _ => ()
        }
        return
      }
    }
    responder.send_json(@core.ok_empty(), headers=[("Content-Type", "application/json; charset=utf-8")]) catch {
      _ => ()
    }
  }

  let root = @mb.Module(ctx => {
    ctx.post("/sys/login", login) catch {
      _ => abort("登录路由注册失败（路由冲突?）")
    }
    ctx.post("/sys/logout", logout) catch {
      _ => abort("注销路由注册失败（路由冲突?）")
    }
    ctx.use_(@sys.module(config, g)) catch {
      e => abort("sys 模块挂载失败: \{e}")
    }
  })
  let app = @mb.App(root)
  defer app.close()
  let server = @mb.listen(host="127.0.0.1", port=18680)
  println("mldong-moon listening on http://127.0.0.1:18680")
  println("端点：POST /sys/login /sys/logout + /sys/user/* /sys/role/*（save/remove/update/detail/page，带鉴权）")
  app.serve(server)
}
