// dev 元数据端点 —— gen 代码生成器与 dev_schema 导入共用的只读面（boot2 SchemaController 同位）。
// 两个端点都直读库目录；dev_schema 台账（importTable 落库）是下一块，disabled 标记随之补。

///|
pub fn schema_policy() -> @guard.RoutePolicy {
  // dbTable 双码 OR（boot2 SaMode.OR 同构：有 dbTable 或 importTable 任一码即可见库表清单）
  let db_table_rule = @guard.RouteRule::make(
    "/dev/schema/dbTable",
    ["dev:schema:dbTable", "dev:schema:importTable"],
  )
  db_table_rule.perm_mode = @port.Or
  @guard.RoutePolicy::new()
    .rule(db_table_rule)
    .rule(@guard.RouteRule::make("/dev/schema/column/list", ["dev:schema:columnList"]))
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, M : @meta.MetadataDao] register(
  ctx : @mb.ModuleContext,
  dao : M,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  // 库表清单（keywords 子串滤表名/注释）
  let db_table_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let keywords = @core.text_or(@web.json_body(request), "keywords", "")
    let tables = dao.list_tables(keywords)
    let arr : Array[Json] = []
    for t in tables {
      arr.push(@dto.table_meta_json(t))
    }
    @core.ok_data(Json::array(arr))
  })
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
  g.post(ctx, "/dev/schema/dbTable", db_table_handler)
  g.post(ctx, "/dev/schema/column/list", column_list_handler)
}
