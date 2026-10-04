// dev 元数据端点 —— gen 代码生成器专用的只读切面（直读 information_schema 裸元数据）。
// 注意与 /dev/schema/* 台账面是两个契约面（base-contract §4 记账）：台账面在
// schema_controller（boot2 同位，disabled/importTable 已落）；本文件只保留 moon 自有的
// column/list（gen 的字段类型映射产物），dbTable 已随台账面合并（disabled 标记进 schema svc）。

///|
pub fn metadata_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new().rule(
    @guard.RouteRule::make("/dev/schema/column/list", ["dev:schema:columnList"]),
  )
}

///|
pub fn[
  S : @port.TokenStore,
  P : @port.PermissionProvider,
  M : @meta.MetadataDao,
] register_metadata(
  ctx : @mb.ModuleContext,
  dao : M,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  // 列清单（ordinal 序 + gen 字段类型映射）
  let column_list_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    let table = @core.text_or(body, "tableName", "")
    if table.is_empty() {
      raise @core.MldongError::InvalidInput("tableName 不能为空")
    }
    let cols = dao.list_columns(table)
    let arr : Array[Json] = []
    for c in cols {
      arr.push(@dto.column_meta_json(c))
    }
    @core.ok_data(Json::array(arr))
  })
  g.post(ctx, "/dev/schema/column/list", column_list_handler)
}
