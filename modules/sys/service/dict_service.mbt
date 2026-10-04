// sys_dict 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait DictService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.DictSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.DictSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.Dict raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.DictPageReq) -> (Int, Array[@entity.Dict]) raise @core.MldongError
  /// getByDictType：DB(启用字典的启用项) → 枚举注册表 → 自定义注册表 → 空数组
  /// （boot2 DictServiceImpl.getByDictType 回退链同构；出口 [{label,value(+ext?)}]，无 id/dataType）
  async fn get_by_dict_type(Self, @core.Ctx, String) -> Array[Json] raise @core.MldongError
  /// 枚举字典清单（boot2 DictScanner/goframe GetEnums 同位；播种器采集源，UC-0431①）
  fn enum_list(Self) -> Array[@dto.DictModel]
  /// 自定义字典清单（goframe GetCustomDict 同位：注册中心存服务不存模型，请求时派生，UC-0432②）
  fn custom_list(Self) -> Array[@dto.DictModel]
}

///|
pub(all) struct DictServiceImpl[R] {
  dao : R
  /// 某字典的启用项（sort 升序）——模块装配闭包注入，服务不依赖 DictItemDao 类型
  items_of : async (Int64) -> Array[@entity.DictItem] raise @core.MldongError
  /// 枚举字典注册表（编译期静态声明；moon 无运行时扫描，boot2 DictScanner 的静态对应物）
  enum_models : Array[@dto.DictModel]
  /// 自定义字典供数方（业务模块注册自己的 list_dict_models 闭包；基础仓零实现 → 空清单）
  custom_providers : Array[() -> Array[@dto.DictModel]]
}

///|
pub impl[R : @dao.DictDao] DictService for DictServiceImpl[R] with fn save(self, ctx, req) {
  // 唯一编码校验（boot2 checkUnique 同位一行调）
  self.dao.check_unique(req.code, None, "唯一编码已存在: " + req.code)
  let d : @entity.Dict = {
    id: @core.next_id(),
    name: req.name,
    code: req.code,
    data_type: req.data_type,
    group_code: req.group_code,
    sort: req.sort,
    enabled: req.enabled,
    remark: req.remark,
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
pub impl[R : @dao.DictDao] DictService for DictServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 编码查重（排除自身）
  self.dao.check_unique(req.code, Some(req.id), "唯一编码已存在: " + req.code)
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.Dict = {
    id: req.id,
    name: req.name,
    code: req.code,
    data_type: req.data_type,
    group_code: req.group_code,
    sort: req.sort,
    enabled: req.enabled,
    remark: req.remark,
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
pub impl[R : @dao.DictDao] DictService for DictServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.DictDao] DictService for DictServiceImpl[R] with fn find_by_id(
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
pub impl[R : @dao.DictDao] DictService for DictServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
/// getByDictType 的出口装配：{label, value(+ext?)}——dataType=2 时 value 转数值
/// （boot2 Convert.toInt 同语义；coerce 失败回落字符串），ext 空不出键
fn dict_item_label_value(d : @entity.Dict, it : @entity.DictItem) -> Json {
  let value : Json = if d.data_type == Some(2) {
    match @core.parse_i64_lenient(it.code) {
      Some(n) => Json::number(n.to_double())
      None => Json::string(it.code)
    }
  } else {
    Json::string(it.code)
  }
  let obj : Json = { "label": Json::string(it.name), "value": value }
  let base = match obj {
    Object(map) => map
    _ => abort("dict_item_label_value 恒为 Object")
  }
  match @core.ext_json_opt(it.variable) {
    Some(e) => {
      let _ = base.set("ext", e)
    }
    None => ()
  }
  Json::object(base)
}

///|
/// 注册表模型 → getByDictType 出口（value 已定型，ext 空不出键）
fn dict_models_to_label_value(items : Array[@dto.DictItemModel]) -> Array[Json] {
  let arr : Array[Json] = []
  for it in items {
    let obj : Json = { "label": Json::string(it.name), "value": it.dict_item_value }
    let base = match obj {
      Object(map) => map
      _ => abort("dict_models_to_label_value 恒为 Object")
    }
    match it.ext {
      Some(e) => {
        let _ = base.set("ext", e)
      }
      None => ()
    }
    arr.push(Json::object(base))
  }
  arr
}

///|
pub impl[R : @dao.DictDao] DictService for DictServiceImpl[R] with fn get_by_dict_type(
  self,
  _ctx,
  dict_type,
) {
  // ① DB：code 命中且启用的字典 → 其启用项（sort 升序，items_of 已排）
  match self.dao.find_enabled_by_code(dict_type) {
    Some(d) => {
      return ((self.items_of)(d.id)).map(fn(it) { dict_item_label_value(d, it) })
    }
    None => ()
  }
  // ② 枚举注册表 → ③ 自定义注册表（请求时派生）→ ④ 空数组（UC-0413 未知类型空数组）
  for m in self.enum_models {
    if m.dict_key == dict_type {
      return dict_models_to_label_value(m.items)
    }
  }
  for provider in self.custom_providers {
    for m in provider() {
      if m.dict_key == dict_type {
        return dict_models_to_label_value(m.items)
      }
    }
  }
  []
}

///|
pub impl[R : @dao.DictDao] DictService for DictServiceImpl[R] with fn enum_list(self) {
  self.enum_models
}

///|
pub impl[R : @dao.DictDao] DictService for DictServiceImpl[R] with fn custom_list(self) {
  let out : Array[@dto.DictModel] = []
  for provider in self.custom_providers {
    for m in provider() {
      out.push(m)
    }
  }
  out
}

///|
/// 枚举字典注册表（boot2 DictScanner / goframe RegisterEnumValues 同位）：
/// dataType 整型码表必填（UC-0431① 播种器唯一采集源），新枚举在数组里加一项
pub fn enum_registry() -> Array[@dto.DictModel] {
  [
    {
      name: "是否",
      dict_key: "yes_no",
      data_type: Some(2),
      items: [
        { name: "启用", dict_item_value: Json::number(1.0), dict_item_key: "1", ext: None },
        { name: "停用", dict_item_value: Json::number(0.0), dict_item_key: "0", ext: None },
      ],
    },
  ]
}

///|
pub extend DictServiceImpl with DictService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
  get_by_dict_type,
  enum_list,
  custom_list,
}
