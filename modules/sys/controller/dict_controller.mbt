// sys_dict 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）
pub fn dict_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/dict/save", ["sys:dict:save"]))
    .rule(@guard.RouteRule::make("/sys/dict/remove", ["sys:dict:remove"]))
    .rule(@guard.RouteRule::make("/sys/dict/update", ["sys:dict:update"]))
    .rule(@guard.RouteRule::make("/sys/dict/detail", ["sys:dict:detail"]))
    .rule(@guard.RouteRule::make("/sys/dict/page", ["sys:dict:page"]))
    .rule(@guard.RouteRule::make("/sys/dict/clearCache", ["sys:dict:clearCache"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.DictService] register_dict(
  ctx : @mb.ModuleContext,
  svc : T,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.dict_parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.dict_parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    let ctx = @web.ctx_of(request)
    @core.ok_data(@dto.dict_json(svc.find_by_id(ctx, id)))
  })
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.dict_parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.dict_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  // getByDictType（仅登录，boot2 同位不加权限码）：[{label,value(+ext?)}]，
  // 未知类型空数组（UC-0413）；出口不带 id/dataType（UC-0431③ 纯增量红线）
  let get_by_type_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let dict_type = @core.text_or(@web.json_body(request), "dictType", "")
    @core.ok_data(Json::array(svc.get_by_dict_type(ctx, dict_type)))
  })
  // enumDictList / customDictList（仅登录）：清单接口，dataType 整型或无键（UC-0431）
  let enum_list_handler : @mb.Handler = @web.wrap(fn(_request) -> Json {
    @core.ok_data(@dto.dict_model_list_json(svc.enum_list()))
  })
  let custom_list_handler : @mb.Handler = @web.wrap(fn(_request) -> Json {
    @core.ok_data(@dto.dict_model_list_json(svc.custom_list()))
  })
  g.post(ctx, "/sys/dict/save", save_handler)
  g.post(ctx, "/sys/dict/remove", remove_handler)
  g.post(ctx, "/sys/dict/update", update_handler)
  g.post(ctx, "/sys/dict/detail", detail_handler)
  g.post(ctx, "/sys/dict/page", page_handler)
  g.post(ctx, "/sys/dict/getByDictType", get_by_type_handler)
  g.post(ctx, "/sys/dict/enumDictList", enum_list_handler)
  g.post(ctx, "/sys/dict/customDictList", custom_list_handler)
  // 清字典缓存（boot2 clearCache 同位）：moon 枚举注册表为启动期快照 + 自定义字典请求时
  // 派生，无运行期缓存可清——幂等空响应保持契约形状（差异记 base-contract §4）
  let clear_cache_handler : @mb.Handler = @web.wrap(fn(_request) -> Json {
    @core.ok_empty()
  })
  g.post(ctx, "/sys/dict/clearCache", clear_cache_handler)
}
