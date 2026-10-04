// dev_schema 服务 —— 业务逻辑唯一收口；零 web/ORM 类型
// 〔cmd/gen 生成 + 台账二开：dbTable/importTable/getByTableName/updateDesigner/keys——
//   boot2 SchemaServiceImpl 对齐；导入消费 MetadataDao（一件两用，gen 同源）〕

///|
pub(open) trait SchemaService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.SchemaSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.SchemaSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.Schema raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.SchemaPageReq) -> (Int, Array[@entity.Schema]) raise @core.MldongError
  /// 库表清单（keywords 滤 + disabled 已导入标记；boot2 dbTable 同形状）
  async fn db_table(Self, @core.Ctx, String) -> Array[Json] raise @core.MldongError
  /// 导入/同步表结构：先删同名历史再重建（boot2 同语义；分组=显式 id 优先→表名首段匹配 group.code）
  async fn import_table(Self, @core.Ctx, Int64?, Array[String]) -> Unit raise @core.MldongError
  /// 按 id 或表名取模型 VO（boot2 detail 的 id 实当 tableName 用 + getByTableName 数字兼容同一解析；
  /// allow_auto_import 时未命中可自愈落库——getByTableName 凭证链专用）
  async fn get_by_id_or_name(Self, @core.Ctx, String, Bool) -> Json raise @core.MldongError
  /// 表单设计保存：update 主表 + 字段全删重插（sort=index+100，事务）
  async fn update_designer(Self, @core.Ctx, @dto.SchemaDesignerReq) -> Json raise @core.MldongError
  /// 列表字段直更（boot2 updateListKeys：id 必填 + keys 文本）
  async fn update_list_keys(Self, @core.Ctx, Int64, String) -> Unit raise @core.MldongError
  /// 搜索表单字段直更（boot2 updateSearchFormKeys）
  async fn update_search_form_keys(Self, @core.Ctx, Int64, String) -> Unit raise @core.MldongError
}

///|
pub(all) struct SchemaServiceImpl[R, F, G, M] {
  dao : R
  fields : F
  groups : G
  meta : M
  /// sys_config 读链（DEFAULT_SCHEMA_AUTO_IMPORT 自愈开关等）
  holder : @core.ConfigHolder
}

///|
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn save(self, ctx, req) {
  let d : @entity.Schema = {
    id: @core.next_id(),
    schema_group_id: req.schema_group_id,
    table_name: req.table_name,
    remark: req.remark,
    other_remark: req.other_remark,
    table_type: req.table_type,
    form_type: req.form_type,
    is_tree: req.is_tree,
    sort: req.sort,
    icon: req.icon,
    search_form_keys: req.search_form_keys,
    list_keys: req.list_keys,
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
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.Schema = {
    id: req.id,
    schema_group_id: req.schema_group_id,
    table_name: req.table_name,
    remark: req.remark,
    other_remark: req.other_remark,
    table_type: req.table_type,
    form_type: req.form_type,
    is_tree: req.is_tree,
    sort: req.sort,
    icon: req.icon,
    search_form_keys: req.search_form_keys,
    list_keys: req.list_keys,
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
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn find_by_id(self, _ctx, id) {
  match self.dao.find_by_id(id) {
    Some(d) => d
    None => raise @core.MldongError::NotFound("数据不存在: " + id.to_string())
  }
}

///|
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn db_table(self, _ctx, keywords) {
  let tables = self.meta.list_tables(keywords)
  let imported : Map[String, Bool] = Map([], capacity=0)
  for name in self.dao.list_imported_names() {
    let _ = imported.set(name, true)
  }
  let arr : Array[Json] = []
  for t in tables {
    arr.push(@dto.table_meta_json(t, imported.get(t.name) is Some(_)))
  }
  arr
}

///|
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn import_table(
  self,
  ctx,
  schema_group_id,
  table_names,
) {
  // 表注释面（boot2 tableInfo.getComment() 同源；一次拉全量按名取）
  let comments : Map[String, String] = Map([], capacity=0)
  for t in self.meta.list_tables("") {
    let _ = comments.set(t.name, t.comment)
  }
  // 清除同名历史模型（boot2：字段物理删 + 模型逻辑删）
  for table_name in table_names {
    match self.dao.find_by_table_name(table_name) {
      Some(his) => {
        self.fields.delete_by_schema_id(his.id)
        self.dao.remove_by_ids([his.id])
      }
      None => ()
    }
  }
  for table_name in table_names {
    let cols = self.meta.list_columns(table_name)
    if cols.is_empty() {
      continue // 物理表不存在（boot2 getTableInfoList 同款静默跳过）
    }
    // 分组解析：显式 schemaGroupId 优先，否则按表名首段匹配 group.code（匹配不到留 None）
    let group_id : Int64? = match schema_group_id {
      Some(g) => Some(g)
      None => {
        let seg = @dto.module_name_of(table_name)
        if seg.is_empty() {
          None
        } else {
          match self.groups.find_by_code(seg) {
            Some(g) => Some(g.id)
            None => None
          }
        }
      }
    }
    let schema_id = @core.next_id()
    let remark = match comments.get(table_name) {
      Some(c) => if c.is_empty() { table_name } else { c }
      None => table_name
    }
    let d : @entity.Schema = {
      id: schema_id,
      schema_group_id: group_id,
      table_name,
      remark,
      other_remark: None,
      table_type: Some(@enums.t_single.code),
      form_type: Some(@enums.f_popup.code),
      is_tree: Some(0), // YesNoEnum.NO
      sort: Some(99L),
      icon: None,
      search_form_keys: None,
      list_keys: None,
      variable: Some(
        "{\"defaultAuthTypeList\":[\"list\",\"save\",\"remove\",\"update\",\"detail\"]}",
      ),
      create_time: Some(@core.now_str()),
      create_user: ctx.user_id,
      update_time: Some(@core.now_str()),
      update_user: ctx.user_id,
      is_deleted: Some(0),
    }
    let _ = self.dao.insert(d)
    let fields : Array[@entity.SchemaField] = []
    let mut list_keys = ""
    let mut idx = 0
    for c in cols {
      if c.name == "is_deleted" {
        continue // 逻辑删除列不导入（boot2 同款过滤）
      }
      let size = parse_field_size(c.column_type)
      let type_code = sql_type_to_enum_code(c.data_type, size.unwrap_or(0))
      let (component, variable) = infer_field_config(
        c.is_pk,
        c.name,
        type_code,
        size.unwrap_or(0),
        table_name,
      )
      fields.push({
        id: @core.next_id(),
        schema_id,
        field_name: c.name,
        remark: if c.comment.is_empty() { c.name } else { c.comment },
        field_size: size,
        data_type: Some(type_code.to_string()),
        is_primary: Some(if c.is_pk { 1 } else { 0 }),
        nullable: Some(if c.is_nullable == "YES" { 1 } else { 0 }),
        default_value: c.default_value,
        component: Some(component),
        sort: Some(idx.to_int64()),
        variable: Some(variable),
        create_time: Some(@core.now_str()),
        create_user: ctx.user_id,
        update_time: Some(@core.now_str()),
        update_user: ctx.user_id,
        is_deleted: Some(0),
      })
      if !list_keys.is_empty() {
        list_keys = list_keys + ","
      }
      list_keys = list_keys + c.name
      idx = idx + 1
    }
    for f in fields {
      let _ = self.fields.insert(f)
    }
    // 默认列表字段 = 全部导入字段（boot2 同款逗号拼接）
    let upd : @entity.Schema = {
      id: schema_id,
      schema_group_id: None,
      table_name: d.table_name,
      remark: d.remark,
      other_remark: None,
      table_type: None,
      form_type: None,
      is_tree: None,
      sort: None,
      icon: None,
      search_form_keys: None,
      list_keys: Some(list_keys),
      variable: None,
      create_time: None,
      create_user: None,
      update_time: Some(@core.now_str()),
      update_user: ctx.user_id,
      is_deleted: None,
    }
    self.dao.update(upd)
  }
}

///|
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn get_by_id_or_name(
  self,
  ctx,
  id_or_name,
  allow_auto_import,
) {
  let mut schema : @entity.Schema? = None
  match parse_i64_or_none(id_or_name) {
    Some(id) => schema = self.dao.find_by_id(id)
    None => schema = self.dao.find_by_table_name(id_or_name)
  }
  // 自愈落库（可选）：未命中 + 非数字 + 凭证链允许 + sys_config 开关 = true
  // （boot2 同款：覆盖策略=已有则跳过，自愈路径 tableName 必不存在于 dev_schema）
  if schema is None && allow_auto_import {
    if self.holder.get_bool("DEFAULT_SCHEMA_AUTO_IMPORT", false) {
      self.import_table(ctx, None, [id_or_name])
      schema = self.dao.find_by_table_name(id_or_name)
    }
  }
  let d = match schema {
    Some(d) => d
    None => raise @core.MldongError::NotFound("数据模型不存在")
  }
  let cols = self.fields.list_by_schema_id(d.id)
  // 分组聚合（boot2：找不到用自身伪造 id=schema.id+1）
  let group : Json = match d.schema_group_id {
    Some(gid) =>
      match self.groups.find_by_id(gid) {
        Some(g) => @dto.schema_group_vo_json(g, self.dao.list_by_group_id(gid))
        None => @dto.schema_group_stub_json(d)
      }
    None => @dto.schema_group_stub_json(d)
  }
  @dto.schema_vo_json(d, cols, group)
}

///|
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn update_designer(self, ctx, req) {
  let body = req.save
  match self.dao.find_by_id(body.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + body.id.to_string())
    Some(_) => ()
  }
  self.update(ctx, body)
  // 字段全删重插（事务在仓储层：DELETE + 批量 INSERT 一个连接收口，boot2 @Transactional 同语义）
  let fields : Array[@entity.SchemaField] = []
  let mut i = 0
  for col in req.columns {
    let creq = @dto.schemafield_req_of(col)
    fields.push({
      id: @core.next_id(),
      schema_id: body.id,
      field_name: creq.field_name,
      remark: creq.remark,
      field_size: creq.field_size,
      data_type: creq.data_type,
      is_primary: creq.is_primary,
      nullable: creq.nullable,
      default_value: creq.default_value,
      component: creq.component,
      sort: Some((i + 100).to_int64()),
      variable: creq.variable,
      create_time: Some(@core.now_str()),
      create_user: ctx.user_id,
      update_time: Some(@core.now_str()),
      update_user: ctx.user_id,
      is_deleted: Some(0),
    })
    i = i + 1
  }
  self.fields.replace_schema_fields(body.id, fields)
  self.get_by_id_or_name(ctx, req.save.table_name, false)
}

///|
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn update_list_keys(self, _ctx, id, keys) {
  match self.dao.find_by_id(id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + id.to_string())
    Some(_) => ()
  }
  self.dao.update_keys(id, "list_keys", keys)
}

///|
pub impl[
  R : @dao.SchemaDao,
  F : @dao.SchemaFieldDao,
  G : @dao.SchemaGroupDao,
  M : @meta.MetadataDao,
] SchemaService for SchemaServiceImpl[R, F, G, M] with fn update_search_form_keys(
  self,
  _ctx,
  id,
  keys,
) {
  match self.dao.find_by_id(id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + id.to_string())
    Some(_) => ()
  }
  self.dao.update_keys(id, "search_form_keys", keys)
}

///|
pub extend SchemaServiceImpl with SchemaService::{
  import_table,
  page,
  db_table,
  remove_by_ids,
  get_by_id_or_name,
  save,
  find_by_id,
  update_list_keys,
  update_designer,
  update,
  update_search_form_keys,
}

///|
/// 数字串解析（boot2 NumberUtil.isNumber + Convert.toLong 同位；失败走名称路径）
fn parse_i64_or_none(s : String) -> Int64? {
  if s.is_empty() {
    return None
  }
  try {
    Some(@string.parse_int64(s))
  } catch {
    _ => None
  }
}

///|
/// column_type 提取长度（"varchar(64)" → Some(64)；无括号/非数字 → None）
fn parse_field_size(column_type : String) -> Int? {
  let open = find_char(column_type, '(')
  let close = find_char(column_type, ')')
  match (open, close) {
    (Some(o), Some(c)) =>
      if c > o + 1 {
        let digits = column_type[o + 1:c].to_owned()
        match parse_i64_or_none(digits) {
          Some(n) => Some(n.to_int())
          None => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn find_char(s : String, target : Char) -> Int? {
  let mut i = 0
  for ch in s {
    if ch == target {
      return Some(i)
    }
    i = i + 1
  }
  None
}
