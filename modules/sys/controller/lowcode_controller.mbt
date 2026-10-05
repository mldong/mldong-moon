// 低代码通用网关 —— goframe lowcode_controller / boot2 LowCodeController 同位：
//   POST /{module}/{table}/select   通用下拉（module+table 拼表名，table 支持小驼峰）
//   POST /sys/user/select           用户下拉专属（labelKey 缺省 real_name，keywords 缺省按它模糊）
//   POST /lowCode/{table}/{page,detail,select}  动态表网关（tableName 为完整 snake 表名）
// 全部仅登录无权限码（goframe `*/*/select` 免权限白名单 / boot2 无注解同口径）。
// 出参：select 裸数组 [{label, value(str), ext?}]；page 五键分页全字段行；detail 全字段。
// 防注入：表名字符白名单 + 真列清单校验 + 值参数绑定（GenericDao 内核）。

///|
/// select 入参提取（goframe base.PageParam 下拉协议；m_ 条件走通用解析）
fn parse_select_req(body : Json) -> @repo.GenericSelectReq {
  {
    page_num: @core.get_int(body, "pageNum").unwrap_or(1),
    page_size: @core.get_int(body, "pageSize").unwrap_or(1000),
    keywords: @core.text_or(body, "keywords", ""),
    search_keys: @core.text_or(body, "searchKeys", ""),
    order_by: @core.text_or(body, "orderBy", ""),
    label_key: @core.text_or(body, "labelKey", ""),
    value_key: @core.text_or(body, "valueKey", ""),
    ext_field_names: @core.text_or(body, "extFieldNames", ""),
    include_type: @core.get_int(body, "includeType").unwrap_or(0),
    include_ids: @core.get_i64_array(body, "includeIds"),
    m: @core.parse_m_params(
      body,
      exclude=[
        "pageNum", "pageSize", "keywords", "searchKeys", "orderBy",
        "labelKey", "valueKey", "extFieldNames", "includeType", "includeIds",
      ],
    ),
  }
}

///|
fn parse_lowcode_page_req(body : Json) -> @repo.GenericPageReq {
  {
    page_num: @core.get_int(body, "pageNum").unwrap_or(1),
    page_size: @core.get_int(body, "pageSize").unwrap_or(10),
    keywords: @core.text_or(body, "keywords", ""),
    search_keys: @core.text_or(body, "searchKeys", ""),
    order_by: @core.text_or(body, "orderBy", ""),
    m: @core.parse_m_params(
      body,
      exclude=["pageNum", "pageSize", "keywords", "searchKeys", "orderBy"],
    ),
  }
}

///|
/// 路径参数取串（moonback router :param；缺省空串）
fn path_param_of(request : @mb.Request, name : String) -> StringView {
  match request.params.get(name) {
    Some(v) => v
    None => ""
  }
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] register_lowcode(
  ctx : @mb.ModuleContext,
  dao : @repo.GenericDao,
  g : @mbguard.Guard[S, P],
) -> Unit {
  // 通用下拉 handler：module/table 取自路由段（table 支持小驼峰 → snake 拼表名）
  let select_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let mod_seg = path_param_of(request, "module").to_owned()
    let table_camel = path_param_of(request, "table").to_owned()
    if mod_seg.is_empty() || table_camel.is_empty() {
      raise @core.MldongError::InvalidInput("module/table 不能为空")
    }
    if !@repo.table_name_safe(mod_seg) {
      raise @core.MldongError::InvalidInput("module 非法")
    }
    let table = mod_seg + "_" + @core.to_underscore(table_camel)
    let arr = dao.select(table, parse_select_req(@web.json_body(request)))
    @core.ok_data(Json::array(arr))
  })
  // lowCode 动态表网关（tableName 为完整 snake 表名）
  let lc_select_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let table = path_param_of(request, "tableName").to_owned()
    let arr = dao.select(table, parse_select_req(@web.json_body(request)))
    @core.ok_data(Json::array(arr))
  })
  let lc_page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let table = path_param_of(request, "tableName").to_owned()
    let req = parse_lowcode_page_req(@web.json_body(request))
    let (total, rows) = dao.page(table, req)
    @core.ok_page(req.page_num, req.page_size, total, rows)
  })
  let lc_detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let table = path_param_of(request, "tableName").to_owned()
    let id = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => raise @core.MldongError::InvalidInput("id 不能为空")
    }
    match dao.detail(table, id) {
      Some(row) => @core.ok_data(row)
      None => raise @core.MldongError::NotFound("数据不存在")
    }
  })
  // /sys/user/select 的 boot2 专属语义（labelKey 缺省 real_name 等）由 user_controller
  // 自带的 select 端点承载（U1 契约 {label,value}），这里不再重复注册——
  // moonback Trie 的 put_route 先查后插：同形静态路由二次注册会 RouteConflict。
  //
  // 注册顺序敏感（moonback Trie 特性）：put_route 对模式串做 search 时，首段 :module
  // 会先撞已存在的静态子再落到根 param 子——若先注册 /:module/:table/select，后注册
  // 的 /lowCode/:tableName/* 会在查型阶段沿 param 链误命中前者的 Route（同深度同尾段）
  // 而炸 RouteConflict。故先挂带静态前缀的 lowCode 路由，再挂 :module 通配。
  g.post(ctx, "/lowCode/:tableName/select", lc_select_handler) catch {
    _ => abort("lowCode select 路由注册失败（路由冲突?）")
  }
  g.post(ctx, "/lowCode/:tableName/page", lc_page_handler) catch {
    _ => abort("lowCode page 路由注册失败（路由冲突?）")
  }
  g.post(ctx, "/lowCode/:tableName/detail", lc_detail_handler) catch {
    _ => abort("lowCode detail 路由注册失败（路由冲突?）")
  }
  g.post(ctx, "/:module/:table/select", select_handler) catch {
    _ => abort("通用 select 路由注册失败（路由冲突?）")
  }
}
