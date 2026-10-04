// dev_schema 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成 + 台账二开：+dbTable/importTable/getByTableName/updateDesigner/keys——
//   boot2 SchemaController 11 端点对齐〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）。
/// OR 组照 boot2 SaMode.OR：detail 三码、dbTable 双码；getByTableName 走豁免面 +
/// handler 内三段自校验（@SaIgnore 同构），不入 rule。
pub fn schema_policy() -> @guard.RoutePolicy {
  let detail_rule = @guard.RouteRule::make(
    "/dev/schema/detail",
    [
      "dev:schema:detail",
      "dev:schema:updateListKeys",
      "dev:schema:updateSearchFormKeys",
    ],
  )
  detail_rule.perm_mode = @port.Or
  let db_table_rule = @guard.RouteRule::make(
    "/dev/schema/dbTable",
    ["dev:schema:dbTable", "dev:schema:importTable"],
  )
  db_table_rule.perm_mode = @port.Or
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/dev/schema/save", ["dev:schema:save"]))
    .rule(@guard.RouteRule::make("/dev/schema/remove", ["dev:schema:remove"]))
    .rule(@guard.RouteRule::make("/dev/schema/update", ["dev:schema:update"]))
    .rule(detail_rule)
    .rule(@guard.RouteRule::make("/dev/schema/page", ["dev:schema:page"]))
    .rule(db_table_rule)
    .rule(@guard.RouteRule::make("/dev/schema/importTable", ["dev:schema:importTable"]))
    .rule(@guard.RouteRule::make("/dev/schema/updateDesigner", ["dev:schema:updateDesigner"]))
    .rule(
      @guard.RouteRule::make("/dev/schema/updateListKeys", ["dev:schema:updateListKeys"]),
    )
    .rule(
      @guard.RouteRule::make(
        "/dev/schema/updateSearchFormKeys",
        ["dev:schema:updateSearchFormKeys"],
      ),
    )
    .exempt("/dev/schema/getByTableName")
}

///|
pub fn[
  S : @port.TokenStore,
  P : @port.PermissionProvider,
  T : @svc.SchemaService,
] register_schema(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
  holder : @core.ConfigHolder,
  auth : @app.TokenAuth[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.schema_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.schema_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  // detail：boot2 的 id 参数实当 tableName 用（getByTableName(StringUtil.toString(id)) 同一解析）
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id_or_name = json_id_as_string(@web.json_body(request))
    @core.ok_data(svc.get_by_id_or_name(ctx, id_or_name, false))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.schema_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.schema_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  // 库表清单（dbTable）：keywords 滤 + disabled 已导入标记（boot2 [{name,comment,disabled}]）
  let db_table_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let keywords = @core.text_or(@web.json_body(request), "keywords", "")
    @core.ok_data(Json::array(svc.db_table(ctx, keywords)))
  })
  // 导入/同步表结构（先删同名历史再重建——破坏性语义与 boot2 一致）
  let import_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let group_id : Int64? = @core.get_i64(body, "schemaGroupId")
    let names : Array[String] = []
    match body {
      Object(map) =>
        match map.get("tableNames") {
          Some(Array(items)) =>
            for it in items {
              match it {
                String(s) => names.push(s)
                _ => ()
              }
            }
          _ => ()
        }
      _ => ()
    }
    if names.is_empty() {
      raise @core.MldongError::InvalidInput("tableNames 不能为空")
    }
    svc.import_table(ctx, group_id, names)
    @core.ok_empty()
  })
  // 按 id 或表名取模型（GET + 豁免面三段自校验：有效登录态 → appId/appSecret → 99990403 信封；
  // 凭证链放行时携带自愈资格，AUTO_IMPORT 开关在 service 判）
  let get_by_name_handler : @mb.Handler = async fn(request, responder) {
    let mut allow_auto = false
    // 豁免路由无主体（principal_of 恒 None）——拿 token 走 auth.is_login 自校验
    let pass = auth.is_login(@web.token_of(request)) || {
      let app_id = header_of(request, "appId")
      let secret = header_of(request, "appSecret")
      if app_id == holder.get("SCHEMA_APP_ID", "admin") &&
        secret == holder.get("SCHEMA_APP_SECRET", "123456") {
        allow_auto = true
        true
      } else {
        false
      }
    }
    if !pass {
      responder.send_json(
        { "code": 99990403, "msg": "无有效凭据", "data": Json::null() },
        headers=[("Content-Type", "application/json; charset=utf-8")],
      ) catch {
        _ => ()
      }
      return
    }
    let table_name = match request.query().get("tableName") {
      Some(v) => v
      None => ""
    }
    if table_name.is_empty() {
      responder.send_json(
        { "code": 99990001, "msg": "tableName 不能为空", "data": Json::null() },
        headers=[("Content-Type", "application/json; charset=utf-8")],
      ) catch {
        _ => ()
      }
      return
    }
    let ctx = @web.ctx_of(request)
    try {
      let vo = svc.get_by_id_or_name(ctx, table_name, allow_auto)
      responder.send_json(
        @core.ok_data(vo),
        headers=[("Content-Type", "application/json; charset=utf-8")],
      ) catch {
        _ => ()
      }
    } catch {
      e => {
        responder.send_json(
          { "code": e.code(), "msg": e.message(), "data": Json::null() },
          headers=[("Content-Type", "application/json; charset=utf-8")],
        ) catch {
          _ => ()
        }
      }
    }
  }
  // 表单设计保存（update 主表 + 字段全删重插，返回最新 VO）
  let designer_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    @core.ok_data(svc.update_designer(ctx, @dto.schema_parse_designer(@web.json_body(request))))
  })
  let list_keys_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let id = match @core.get_i64(body, "id") {
      Some(n) => n
      None => 0L
    }
    if id <= 0L {
      raise @core.MldongError::InvalidInput("SchemaID不能为空")
    }
    svc.update_list_keys(ctx, id, @core.text_or(body, "listKeys", ""))
    @core.ok_empty()
  })
  let search_keys_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let body = @web.json_body(request)
    let id = match @core.get_i64(body, "id") {
      Some(n) => n
      None => 0L
    }
    if id <= 0L {
      raise @core.MldongError::InvalidInput("SchemaID不能为空")
    }
    svc.update_search_form_keys(ctx, id, @core.text_or(body, "searchFormKeys", ""))
    @core.ok_empty()
  })
  g.post(ctx, "/dev/schema/save", save_handler)
  g.post(ctx, "/dev/schema/remove", remove_handler)
  g.post(ctx, "/dev/schema/update", update_handler)
  g.post(ctx, "/dev/schema/detail", detail_handler)
  g.post(ctx, "/dev/schema/page", page_handler)
  g.post(ctx, "/dev/schema/dbTable", db_table_handler)
  g.post(ctx, "/dev/schema/importTable", import_handler)
  ctx.get("/dev/schema/getByTableName", get_by_name_handler) catch {
    _ => abort("getByTableName 路由注册失败（路由冲突?）")
  }
  g.post(ctx, "/dev/schema/updateDesigner", designer_handler)
  g.post(ctx, "/dev/schema/updateListKeys", list_keys_handler)
  g.post(ctx, "/dev/schema/updateSearchFormKeys", search_keys_handler)
}

///|
/// 请求头读取（剥离视图；空缺返回空串）
fn header_of(request : @mb.Request, name : String) -> String {
  match request.headers.get(name) {
    Some(v) => v.to_owned()
    None => ""
  }
}

///|
/// body.id 兼容取串（boot2 StrUtil.toString(param.getId()) 同位：数字雪花/字符串表名二态）
fn json_id_as_string(body : Json) -> String {
  match body {
    Object(map) =>
      match map.get("id") {
        Some(String(s)) => s
        // 数字走 get_i64 同一转换（Double::to_int64 截断，雪花大数前端本就走字符串）
        Some(Number(_)) =>
          match @core.get_i64(body, "id") {
            Some(n) => n.to_string()
            None => ""
          }
        _ => ""
      }
    _ => ""
  }
}
