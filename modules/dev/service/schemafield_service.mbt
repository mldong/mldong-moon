// dev_schema_field 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait SchemaFieldService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.SchemaFieldSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.SchemaFieldSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.SchemaField raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.SchemaFieldPageReq) -> (Int, Array[@entity.SchemaField]) raise @core.MldongError
  /// 拖拽排序（boot2 updateSort 同算法：拖拽行取 hover sort、hover ±1、区间外不动）
  async fn update_sort(Self, @core.Ctx, Int64, Int64, Int64) -> Unit raise @core.MldongError
}

///|
pub(all) struct SchemaFieldServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.SchemaFieldDao] SchemaFieldService for SchemaFieldServiceImpl[R] with fn save(self, ctx, req) {
  let d : @entity.SchemaField = {
    id: @core.next_id(),
    schema_id: req.schema_id,
    field_name: req.field_name,
    remark: req.remark,
    field_size: req.field_size,
    data_type: req.data_type,
    is_primary: req.is_primary,
    nullable: req.nullable,
    default_value: req.default_value,
    component: req.component,
    sort: req.sort,
    variable: req.variable,
    create_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: Some(0),
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.SchemaFieldDao] SchemaFieldService for SchemaFieldServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.SchemaField = {
    id: req.id,
    schema_id: req.schema_id,
    field_name: req.field_name,
    remark: req.remark,
    field_size: req.field_size,
    data_type: req.data_type,
    is_primary: req.is_primary,
    nullable: req.nullable,
    default_value: req.default_value,
    component: req.component,
    sort: req.sort,
    variable: req.variable,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: None,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.SchemaFieldDao] SchemaFieldService for SchemaFieldServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  // 物理删（boot2 SchemaField 的 @TableLogic 被注释掉，remove 即硬删，page 靠 is_deleted=0 过滤）
  self.dao.delete_by_ids(ids)
}

///|
pub impl[R : @dao.SchemaFieldDao] SchemaFieldService for SchemaFieldServiceImpl[R] with fn find_by_id(
  self,
  _ctx,
  id,
) {
  match self.dao.find_by_id(id) {
    Some(d) => d
    None => raise @core.MldongError::NotFound("数据不存在: " + id.to_string())
  }
}

///|
pub impl[R : @dao.SchemaFieldDao] SchemaFieldService for SchemaFieldServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub impl[R : @dao.SchemaFieldDao] SchemaFieldService for SchemaFieldServiceImpl[R] with fn update_sort(
  self,
  _ctx,
  schema_id,
  drag_row_id,
  hover_row_id,
) {
  let list = self.dao.list_by_schema_id(schema_id)
  let ids : Array[Int64] = []
  let sorts : Array[Int64] = []
  for f in list {
    ids.push(f.id)
    sorts.push(f.sort.unwrap_or(0L))
  }
  for pair in drag_sort_plan(ids, sorts, drag_row_id, hover_row_id) {
    self.dao.update_sort_value(pair.0, pair.1)
  }
}

///|
pub extend SchemaFieldServiceImpl with SchemaFieldService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
  update_sort,
}
