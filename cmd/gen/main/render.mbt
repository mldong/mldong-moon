// 六件套渲染 —— 模板对齐 modules/sys 的 user 样板（house style）。
// 生成物不用字符串插值（统一 + 拼接），生成器模板自身就零转义坑。

///|
pub(all) struct TablePlan {
  /// 表名（sys_dept）
  table : String
  /// 类名（Dept）
  class_name : String
  /// 权限码前缀（sys:dept）
  perm : String
  /// 小写文件名基（dept）
  lc : String
  /// 归一列
  cols : Array[Col]
  /// 有 code 唯一编码列
  has_code : Bool
}

///|
fn TablePlan::business_cols(self : TablePlan) -> Array[Col] {
  // 主键不在业务面（id 在各模板显式处理，进这里会重复）
  self.cols.filter(fn(c) { c.business && !c.is_pk })
}

///|
/// 类型 → 写路包装名（plain / opt 两族）
fn wrapper_of(c : Col) -> String {
  let base = if c.ftype == "Int64" {
    "L"
  } else if c.ftype == "Int" {
    "I"
  } else {
    "S"
  }
  if c.option {
    "opt_" + base_to_opt(base)
  } else {
    base
  }
}

///|
fn base_to_opt(base : String) -> String {
  if base == "L" {
    "l"
  } else if base == "I" {
    "i"
  } else {
    "s"
  }
}

///|
/// 行读取器名（plain / opt 两族）
fn reader_of(c : Col) -> String {
  if c.ftype == "Int64" {
    if c.option {
      "row_opt_i64"
    } else {
      "row_i64"
    }
  } else if c.ftype == "Int" {
    if c.option {
      "row_opt_int"
    } else {
      "row_int_d"
    }
  } else if c.option {
    "row_opt_text"
  } else {
    "row_text"
  }
}

///|
/// 文本行累积器
struct Out {
  buf : StringBuilder
}

///|
fn Out::new() -> Out {
  { buf: StringBuilder() }
}

///|
fn Out::line(self : Out, s : String) -> Unit {
  self.buf.write_string(s)
  self.buf.write_char('\n')
}

///|
fn Out::text(self : Out) -> String {
  self.buf.to_string()
}

///|
/// 字段声明行（实体/Req 共用形状）
fn field_line(o : Out, c : Col) -> Unit {
  let t = if c.option { c.ftype + "?" } else { c.ftype }
  o.line("  mut " + c.name + " : " + t)
}

///|
/// entity/<lc>.mbt
pub fn render_entity(plan : TablePlan) -> String {
  let o = Out::new()
  o.line("// " + plan.table + " 实体 —— 纯数据，零框架类型；类名去表前缀（" + plan.table + " → " + plan.class_name + "）")
  o.line("// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕")
  o.line("")
  o.line("///|")
  o.line("pub(all) struct " + plan.class_name + " {")
  o.line("  mut id : Int64")
  for c in plan.cols {
    if c.is_pk {
      continue
    }
    field_line(o, c)
  }
  o.line("}")
  o.text()
}

///|
/// dto/<lc>_dto.mbt
pub fn render_dto(plan : TablePlan) -> String {
  let o = Out::new()
  let biz = plan.business_cols()
  o.line("// " + plan.table + " 入参契约 —— schema + parse + Req（moon_zod 唯一入口）；出参装配同层")
  o.line("// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕")
  o.line("")
  o.line("///|")
  o.line("/// save/update 共用（update 要求 id > 0，parse_update 里校验）")
  o.line("pub(all) struct " + plan.class_name + "SaveReq {")
  o.line("  mut id : Int64")
  for c in biz {
    field_line(o, c)
  }
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("let " + plan.lc + "_save_schema : @moon_zod.Schema = @moon_zod.object({")
  o.line("  // 雪花 id 进出不参与校验，strip 模式下用 any().optional() 占位存活")
  o.line("  \"id\": @moon_zod.any().optional(),")
  for c in biz {
    let k = "\"" + c.json + "\""
    if c.ftype == "Int64" {
      o.line("  " + k + ": @moon_zod.any().optional(),")
    } else if c.ftype == "Int" {
      if c.option {
        o.line("  " + k + ": @moon_zod.number().int().optional(),")
      } else {
        o.line("  " + k + ": @moon_zod.number().int(),")
      }
    } else {
      let mut rule = "@moon_zod.string()"
      match c.max_len {
        Some(n) => rule = rule + ".max(" + n.to_string() + ", msg=\"" + c.json + " 最多 " + n.to_string() + " 位\")"
        None => ()
      }
      if c.option {
        rule = rule + ".optional()"
      }
      o.line("  " + k + ": " + rule + ",")
    }
  }
  o.line("})")
  o.line("")
  o.line("///|")
  o.line("/// 从 Json 提取 Req")
  o.line("fn " + plan.lc + "_req_of(data : Json) -> " + plan.class_name + "SaveReq {")
  o.line("  {")
  o.line("    id: @core.get_i64(data, \"id\").unwrap_or(0L),")
  for c in biz {
    let k = "\"" + c.json + "\""
    if c.ftype == "Int64" {
      o.line("    " + c.name + ": @core.get_i64(data, " + k + "),")
    } else if c.ftype == "Int" {
      o.line("    " + c.name + ": @core.get_int(data, " + k + "),")
    } else {
      if c.option {
        o.line("    " + c.name + ": @core.get_text(data, " + k + "),")
      } else {
        o.line("    " + c.name + ": @core.text_or(data, " + k + ", \"\"),")
      }
    }
  }
  o.line("  }")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub fn " + plan.lc + "_parse_save(body : Json) -> " + plan.class_name + "SaveReq raise @core.MldongError {")
  o.line("  match " + plan.lc + "_save_schema.parse(body) {")
  o.line("    Ok(data) => " + plan.lc + "_req_of(data)")
  o.line("    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())")
  o.line("  }")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub fn " + plan.lc + "_parse_update(body : Json) -> " + plan.class_name + "SaveReq raise @core.MldongError {")
  o.line("  let req = " + plan.lc + "_parse_save(body)")
  o.line("  if req.id <= 0L {")
  o.line("    raise @core.MldongError::InvalidInput(\"" + plan.class_name + "ID不能为空\")")
  o.line("  }")
  o.line("  req")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("/// 分页入参：m_* 动态条件由 core 通用查询件解析，keywords 交 service 按列白名单应用")
  o.line("pub(all) struct " + plan.class_name + "PageReq {")
  o.line("  page_num : Int")
  o.line("  page_size : Int")
  o.line("  m : @core.Wrapper")
  o.line("  keywords : String")
  o.line("  search_keys : String")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub fn " + plan.lc + "_parse_page(body : Json) -> " + plan.class_name + "PageReq raise @core.MldongError {")
  o.line("  let page_num = @core.get_int(body, \"pageNum\").unwrap_or(1)")
  o.line("  let page_size = @core.get_int(body, \"pageSize\").unwrap_or(10)")
  o.line("  if page_num <= 0 || page_size <= 0 || page_size > 200 {")
  o.line("    raise @core.MldongError::InvalidInput(\"分页参数非法\")")
  o.line("  }")
  o.line("  {")
  o.line("    page_num,")
  o.line("    page_size,")
  o.line("    m: @core.parse_m_params(body, exclude=[\"pageNum\", \"pageSize\", \"keywords\", \"searchKeys\"]),")
  o.line("    keywords: @core.text_or(body, \"keywords\", \"\"),")
  o.line("    search_keys: @core.text_or(body, \"searchKeys\", \"\"),")
  o.line("  }")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("/// 出参装配：<Cls> → Json（camelCase；雪花 id 一律字符串化防 JS 精度丢失）")
  o.line("pub fn " + plan.lc + "_json(d : @entity." + plan.class_name + ") -> Json {")
  o.line("  {")
  o.line("    \"id\": d.id.to_string(),")
  for c in plan.cols {
    if c.is_pk {
      continue
    }
    let k = "\"" + c.json + "\""
    if c.ftype == "Int64" {
      o.line("    " + k + ": jsnow(d." + c.name + "),")
    } else if c.ftype == "Int" {
      if c.option {
        o.line("    " + k + ": jint(d." + c.name + "),")
      } else {
        o.line("    " + k + ": Json::number(d." + c.name + ".to_double()),")
      }
    } else {
      if c.option {
        o.line("    " + k + ": jstr(d." + c.name + "),")
      } else {
        o.line("    " + k + ": Json::string(d." + c.name + "),")
      }
    }
  }
  o.line("  }")
  o.line("}")
  o.text()
}

///|
/// dao/<lc>_dao.mbt
pub fn render_dao(plan : TablePlan) -> String {
  let o = Out::new()
  o.line("// " + plan.table + " 仓储端口 —— 签名只用 entity/core 类型（Wrapper 为 core 零 ORM 条件组）")
  o.line("// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕")
  o.line("")
  o.line("///|")
  o.line("pub(open) trait " + plan.class_name + "Dao {")
  o.line("  async fn insert(Self, @entity." + plan.class_name + ") -> Int64 raise @core.MldongError")
  o.line("  async fn update(Self, @entity." + plan.class_name + ") -> Unit raise @core.MldongError")
  o.line("  /// 逻辑删除（表配置驱动）")
  o.line("  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError")
  o.line("  async fn find_by_id(Self, Int64) -> @entity." + plan.class_name + "? raise @core.MldongError")
  o.line("  /// 批量按 id 查（remove 前收标识刷缓存等场景）")
  o.line("  async fn find_by_ids(Self, Array[Int64]) -> Array[@entity." + plan.class_name + "] raise @core.MldongError")
  if plan.has_code {
    o.line("  /// 唯一编码校验（boot2 checkUnique 同位一行调：存在且排除自身即 Conflict）")
    o.line("  async fn check_unique(Self, String, Int64?, String) -> Unit raise @core.MldongError")
  }
  o.line("  /// 分页：Wrapper 由 service 组装（业务说了算），返回 (总数, 当页行)")
  o.line("  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity." + plan.class_name + "]) raise @core.MldongError")
  o.line("}")
  o.text()
}

///|
/// dao-mysql/<lc>_table.mbt
pub fn render_table(plan : TablePlan) -> String {
  let o = Out::new()
  o.line("// " + plan.table + " 表编解码器 —— BaseDao 模板的每实体配置〔cmd/gen 生成，可手改〕")
  o.line("")
  o.line("///|")
  o.line("let " + plan.lc + "_table : TableCodec[@entity." + plan.class_name + "] = TableCodec::{")
  o.line("  name: \"" + plan.table + "\",")
  o.line("  cols: [")
  for c in plan.cols {
    o.line("    \"" + c.name + "\",")
  }
  o.line("  ],")
  o.line("  insert_cols: [")
  o.line("    { name: \"id\", get: fn(d) { L(d.id) } },")
  for c in plan.business_cols() {
    o.line("    { name: \"" + c.name + "\", get: fn(d) { " + wrapper_of(c) + "(d." + c.name + ") } },")
  }
  o.line("    { name: \"create_time\", get: fn(d) { S(match d.create_time { Some(s) => s; None => @core.now_str() }) } },")
  o.line("    { name: \"create_user\", get: fn(d) { opt_l(d.create_user) } },")
  o.line("    { name: \"update_user\", get: fn(d) { opt_l(d.update_user) } },")
  o.line("  ],")
  o.line("  update_cols: [")
  for c in plan.business_cols() {
    o.line("    { name: \"" + c.name + "\", get: fn(d) { " + wrapper_of(c) + "(d." + c.name + ") } },")
  }
  o.line("    { name: \"update_time\", get: fn(_d) { S(@core.now_str()) } },")
  o.line("    { name: \"update_user\", get: fn(d) { opt_l(d.update_user) } },")
  o.line("  ],")
  o.line("  from_row: row_" + plan.lc + ",")
  o.line("  id_of: fn(d) { L(d.id) },")
  o.line("  del_col: Some(\"is_deleted\"),")
  let order = if plan.cols.filter(fn(c) { c.name == "create_time" }).length() > 0 {
    "create_time"
  } else {
    "id"
  }
  o.line("  order_col: \"" + order + "\",")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("/// 行映射按列名取 —— MyBatis resultMap 的手写对应物")
  o.line("fn row_" + plan.lc + "(r : @moondb.Row) -> @entity." + plan.class_name + " {")
  o.line("  {")
  o.line("    id: row_i64(r, \"id\"),")
  for c in plan.cols {
    if c.is_pk {
      continue
    }
    let rn = reader_of(c)
    if rn == "row_text" {
      o.line("    " + c.name + ": row_text(r, \"" + c.name + "\", \"\"),")
    } else if rn == "row_int_d" {
      o.line("    " + c.name + ": row_int_d(r, \"" + c.name + "\", 0),")
    } else {
      o.line("    " + c.name + ": " + rn + "(r, \"" + c.name + "\"),")
    }
  }
  o.line("  }")
  o.line("}")
  o.text()
}

///|
/// dao-mysql/<lc>_mysql.mbt
pub fn render_mysql(plan : TablePlan) -> String {
  let o = Out::new()
  o.line("// " + plan.table + " MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板")
  o.line("// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕")
  o.line("")
  o.line("///|")
  o.line("pub(all) struct " + plan.class_name + "MysqlDao {")
  o.line("  base : BaseDao[@entity." + plan.class_name + "]")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub fn " + plan.class_name + "MysqlDao::make(config : @core.MysqlConfig) -> " + plan.class_name + "MysqlDao {")
  o.line("  { base: { config, table: " + plan.lc + "_table } }")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl @dao." + plan.class_name + "Dao for " + plan.class_name + "MysqlDao with fn insert(self, d) {")
  o.line("  self.base.insert(d)")
  o.line("  d.id")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl @dao." + plan.class_name + "Dao for " + plan.class_name + "MysqlDao with fn update(self, d) {")
  o.line("  self.base.update_by_id(d)")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl @dao." + plan.class_name + "Dao for " + plan.class_name + "MysqlDao with fn remove_by_ids(self, ids) {")
  o.line("  let vals : Array[@core.SqlValue] = []")
  o.line("  for id in ids {")
  o.line("    vals.push(L(id))")
  o.line("  }")
  o.line("  self.base.remove_by_ids(vals)")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl @dao." + plan.class_name + "Dao for " + plan.class_name + "MysqlDao with fn find_by_id(self, id) {")
  o.line("  self.base.find_by_id(L(id))")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl @dao." + plan.class_name + "Dao for " + plan.class_name + "MysqlDao with fn find_by_ids(self, ids) {")
  o.line("  let vals : Array[@core.SqlValue] = []")
  o.line("  for id in ids {")
  o.line("    vals.push(L(id))")
  o.line("  }")
  o.line("  self.base.find_by_ids(vals)")
  o.line("}")
  if plan.has_code {
    o.line("")
    o.line("///|")
    o.line("pub impl @dao." + plan.class_name + "Dao for " + plan.class_name + "MysqlDao with fn check_unique(")
    o.line("  self,")
    o.line("  code,")
    o.line("  exclude_id,")
    o.line("  msg,")
    o.line(") {")
    o.line("  self.base.check_unique(\"code\", S(code), exclude_id, msg)")
    o.line("}")
  }
  o.line("")
  o.line("///|")
  o.line("pub impl @dao." + plan.class_name + "Dao for " + plan.class_name + "MysqlDao with fn page(self, w, page_num, page_size) {")
  o.line("  self.base.page(w, page_num, page_size)")
  o.line("}")
  o.line("")
  let exports : Array[String] = ["remove_by_ids", "find_by_id", "insert", "update", "page", "find_by_ids"]
  o.line("pub extend " + plan.class_name + "MysqlDao with @dao." + plan.class_name + "Dao::{")
  for e in exports {
    o.line("  " + e + ",")
  }
  o.line("}")
  o.text()
}

///|
/// service/<lc>_service.mbt
pub fn render_service(plan : TablePlan) -> String {
  let o = Out::new()
  o.line("// " + plan.table + " 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕")
  o.line("")
  o.line("///|")
  o.line("pub(open) trait " + plan.class_name + "Service {")
  o.line("  /// op_user = 操作人 id（审计 create_user/update_user；controller 从登录主体取）")
  o.line("  async fn save(Self, @dto." + plan.class_name + "SaveReq, Int64?) -> Int64 raise @core.MldongError")
  o.line("  async fn update(Self, @dto." + plan.class_name + "SaveReq, Int64?) -> Unit raise @core.MldongError")
  o.line("  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError")
  o.line("  async fn find_by_id(Self, Int64) -> @entity." + plan.class_name + " raise @core.MldongError")
  o.line("  async fn page(Self, @dto." + plan.class_name + "PageReq) -> (Int, Array[@entity." + plan.class_name + "]) raise @core.MldongError")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub(all) struct " + plan.class_name + "ServiceImpl[R] {")
  o.line("  dao : R")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl[R : @dao." + plan.class_name + "Dao] " + plan.class_name + "Service for " + plan.class_name + "ServiceImpl[R] with fn save(self, req, op_user) {")
  if plan.has_code {
    o.line("  // 唯一编码校验（boot2 checkUnique 同位一行调）")
    o.line("  self.dao.check_unique(req.code, None, \"唯一编码已存在: \" + req.code)")
  }
  o.line("  let d : @entity." + plan.class_name + " = {")
  o.line("    id: @core.next_id(),")
  for c in plan.business_cols() {
    o.line("    " + c.name + ": req." + c.name + ",")
  }
  for c in plan.cols {
    if !c.business && !c.is_pk && c.name != "create_time" && c.name != "update_time" && c.name != "create_user" && c.name != "update_user" && c.name != "is_deleted" {
      o.line("    " + c.name + ": None,")
    }
  }
  o.line("    create_time: Some(@core.now_str()),")
  o.line("    create_user: op_user,")
  o.line("    update_time: None,")
  o.line("    update_user: op_user,")
  o.line("    is_deleted: Some(0),")
  o.line("  }")
  o.line("  self.dao.insert(d)")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl[R : @dao." + plan.class_name + "Dao] " + plan.class_name + "Service for " + plan.class_name + "ServiceImpl[R] with fn update(self, req, op_user) {")
  o.line("  match self.dao.find_by_id(req.id) {")
  o.line("    None => raise @core.MldongError::NotFound(\"数据不存在: \" + req.id.to_string())")
  o.line("    Some(_) => ()")
  o.line("  }")
  if plan.has_code {
    o.line("  // 编码查重（排除自身）")
    o.line("  self.dao.check_unique(req.code, Some(req.id), \"唯一编码已存在: \" + req.code)")
  }
  o.line("  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）")
  o.line("  let d : @entity." + plan.class_name + " = {")
  o.line("    id: req.id,")
  for c in plan.business_cols() {
    o.line("    " + c.name + ": req." + c.name + ",")
  }
  for c in plan.cols {
    if !c.business && !c.is_pk && c.name != "create_time" && c.name != "update_time" && c.name != "create_user" && c.name != "update_user" && c.name != "is_deleted" {
      o.line("    " + c.name + ": None,")
    }
  }
  o.line("    create_time: None,")
  o.line("    create_user: None,")
  o.line("    update_time: Some(@core.now_str()),")
  o.line("    update_user: op_user,")
  o.line("    is_deleted: None,")
  o.line("  }")
  o.line("  self.dao.update(d)")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl[R : @dao." + plan.class_name + "Dao] " + plan.class_name + "Service for " + plan.class_name + "ServiceImpl[R] with fn remove_by_ids(self, ids) {")
  o.line("  if ids.is_empty() {")
  o.line("    raise @core.MldongError::InvalidInput(\"ids 不能为空\")")
  o.line("  }")
  o.line("  self.dao.remove_by_ids(ids)")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl[R : @dao." + plan.class_name + "Dao] " + plan.class_name + "Service for " + plan.class_name + "ServiceImpl[R] with fn find_by_id(")
  o.line("  self,")
  o.line("  id,")
  o.line(") {")
  o.line("  match self.dao.find_by_id(id) {")
  o.line("    Some(d) => d")
  o.line("    None => raise @core.MldongError::NotFound(\"数据不存在: \" + id.to_string())")
  o.line("  }")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub impl[R : @dao." + plan.class_name + "Dao] " + plan.class_name + "Service for " + plan.class_name + "ServiceImpl[R] with fn page(self, req) {")
  o.line("  let w = @core.where_()")
  o.line("  let _ = w.append(req.m)")
  o.line("  self.dao.page(w, req.page_num, req.page_size)")
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub extend " + plan.class_name + "ServiceImpl with " + plan.class_name + "Service::{")
  o.line("  page,")
  o.line("  remove_by_ids,")
  o.line("  save,")
  o.line("  find_by_id,")
  o.line("  update,")
  o.line("}")
  o.text()
}

///|
/// controller/<lc>_controller.mbt
pub fn render_controller(plan : TablePlan) -> String {
  let o = Out::new()
  // 路由前缀 = 表名首下划线换 /（sys_dept → /sys/dept）；权限码前缀另算（sys:dept）
  let route_base = match plan.table.find("_") {
    Some(i) =>
      "/" + plan.table.substring(start=0, end=i) + "/" + plan.table.substring(start=i + 1)
    None => "/" + plan.table
  }
  o.line("// " + plan.table + " 控制器 —— 手写薄端点（校验在 dto、业务在 service、响应工具在 core）")
  o.line("// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕")
  o.line("")
  o.line("///|")
  o.line("/// 权限码片段——与端点同文件声明；全部显式 rule（推导兜底已被 main 关闭）")
  o.line("pub fn " + plan.lc + "_policy() -> @guard.RoutePolicy {")
  o.line("  @guard.RoutePolicy::new()")
  for act in ["save", "remove", "update", "detail", "page"] {
    o.line("    .rule(@guard.RouteRule::make(\"" + route_base + "/" + act + "\", [\"" + plan.perm + ":" + act + "\"]))")
  }
  o.line("}")
  o.line("")
  o.line("///|")
  o.line("pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc." + plan.class_name + "Service] register_" + plan.lc + "(")
  o.line("  ctx : @mb.ModuleContext,")
  o.line("  svc : T,")
  o.line("  g : @mbguard.Guard[S, P],")
  o.line(") -> Unit raise {")
  o.line("  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {")
  o.line("    let op_user = @web.user_id_of(request)")
  o.line("    let id = svc.save(@dto." + plan.lc + "_parse_save(@web.json_body(request)), op_user)")
  o.line("    @core.ok_data(Json::string(id.to_string()))")
  o.line("  })")
  o.line("  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {")
  o.line("    svc.remove_by_ids(@core.get_ids(@web.json_body(request)))")
  o.line("    @core.ok_empty()")
  o.line("  })")
  o.line("  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {")
  o.line("    let op_user = @web.user_id_of(request)")
  o.line("    svc.update(@dto." + plan.lc + "_parse_update(@web.json_body(request)), op_user)")
  o.line("    @core.ok_empty()")
  o.line("  })")
  o.line("  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {")
  o.line("    let id : Int64 = match @core.get_i64(@web.json_body(request), \"id\") {")
  o.line("      Some(n) => n")
  o.line("      None => 0L")
  o.line("    }")
  o.line("    @core.ok_data(@dto." + plan.lc + "_json(svc.find_by_id(id)))")
  o.line("  })")
  o.line("  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {")
  o.line("    let req = @dto." + plan.lc + "_parse_page(@web.json_body(request))")
  o.line("    let (total, rows) = svc.page(req)")
  o.line("    let arr : Array[Json] = []")
  o.line("    for row in rows {")
  o.line("      arr.push(@dto." + plan.lc + "_json(row))")
  o.line("    }")
  o.line("    @core.ok_page(req.page_num, req.page_size, total, arr)")
  o.line("  })")
  for act in ["save", "remove", "update", "detail", "page"] {
    o.line("  g.post(ctx, \"" + route_base + "/" + act + "\", " + snake_act(act) + "_handler) catch {")
    o.line("    e => raise e")
    o.line("  }")
  }
  o.line("}")
  o.text()
}

///|
fn snake_act(act : String) -> String {
  // save/remove/update/detail/page 全是单词，直接透传（复合动作名未来在此扩展）
  act
}

///|
/// 渲染全部文件 → (相对路径, 内容) 列表
pub fn render_all(plan : TablePlan) -> Array[(String, String)] {
  [
    ("entity/" + plan.lc + ".mbt", render_entity(plan)),
    ("dto/" + plan.lc + "_dto.mbt", render_dto(plan)),
    ("dao/" + plan.lc + "_dao.mbt", render_dao(plan)),
    ("dao-mysql/" + plan.lc + "_table.mbt", render_table(plan)),
    ("dao-mysql/" + plan.lc + "_mysql.mbt", render_mysql(plan)),
    ("service/" + plan.lc + "_service.mbt", render_service(plan)),
    ("controller/" + plan.lc + "_controller.mbt", render_controller(plan)),
  ]
}
