// app 检查升级控制器 —— UC-0610（06-文件杂项，2026-09-20 定稿，基准 goframe fd88b94）。
//
// 契约（runner 三断言全环境无关）：
//   ① platform 越界 → 99999999 + 具体 msg（HTTP 恒 200；boot2 @Validated 统一 99999999）
//   ② 缺 versionCode → 99999999
//   ③ 免登录 + versionCode 高于任何已发布 → code 0 + data=null
//
// 蒲公英转调：env PGYER_API_KEY + PGYER_APP_KEY_ANDROID/HARMONYOS/IOS（真值不进仓库）。
// **moon 档现无外呼 HTTP/TLS 客户端**（moonrun wasm 档无 outbound HTTP；moonbitstack/moontls
// 成熟后接真转调）——有 key 也按"第三方失败"降级 data=null + 注释留痕，契约三态同判不受影响
// （UC-0610 明文：任何失败降级 data null 不阻塞 App 启动；hasUpdate=true 正向分支本就不进
// runner，由各栈真值手工 curl 矩阵覆盖）。

///|
pub fn app_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new().exempt("/app/appVersion/check")
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] register(
  ctx : @mb.ModuleContext,
  g : @mbguard.Guard[S, P],
) -> Unit {
  let check_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let _ = request // 免登录：不取主体
    let body = @web.json_body(request)
    // platform：1=Android 2=HarmonyOS 3=iOS（boot2 @NotNull @Min1 @Max3 同口径）
    let platform = match @core.get_int(body, "platform") {
      Some(n) => n
      None => raise @core.MldongError::InvalidParam("platform 不能为空")
    }
    if platform < 1 || platform > 3 {
      raise @core.MldongError::InvalidParam("platform 必须在 1..3（1=Android 2=HarmonyOS 3=iOS）")
    }
    // versionCode：口径=蒲公英 buildVersionNo（boot2 @NotNull @Min1）
    let version_code = match @core.get_i64(body, "versionCode") {
      Some(n) => n
      None => raise @core.MldongError::InvalidParam("versionCode 不能为空")
    }
    if version_code < 1L {
      raise @core.MldongError::InvalidParam("versionCode 必须大于等于 1")
    }
    // 转调蒲公英（apiv2/app/check）：配了 key 走外呼比较，任何失败降级 data=null。
    // moon 档外呼客户端未接（见文件头）——恒走降级分支；待 moontls 成熟补真比较。
    let _ = pgyer_app_key_of(platform) // 读了：未配/已配都降级，仅留读痕供未来接外呼
    @core.ok_data(Json::null())
  })
  g.post(ctx, "/app/appVersion/check", check_handler) catch {
    _ => abort("appVersion/check 路由注册失败（路由冲突?）")
  }
}

///|
/// 平台 → 蒲公英 appKey（env 字典式：PGYER_APP_KEY_ANDROID/HARMONYOS/IOS；
/// 未配该平台返回空串——boot2 未配平台返 null 同判）
fn pgyer_app_key_of(platform : Int) -> String {
  let key = match platform {
    1 => "PGYER_APP_KEY_ANDROID"
    2 => "PGYER_APP_KEY_HARMONYOS"
    3 => "PGYER_APP_KEY_IOS"
    _ => ""
  }
  match @env.get_env_var(key) {
    Some(v) => v
    None => ""
  }
}
