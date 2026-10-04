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
/// 枚举字典项速记（label=枚举 message、value=枚举 code；dataType 全 2 整型码）
fn ei(label : String, value : Int) -> @dto.DictItemModel {
  {
    name: label,
    dict_item_value: Json::number(value.to_double()),
    dict_item_key: value.to_string(),
    ext: None,
  }
}

///|
/// 枚举字典注册表（boot2 DictScanner / goframe RegisterEnumValues 同位）：
/// 与 boot2 @DictEnum 的 sys 域 + 基础件逐项对齐（18 个，同 key 同名同码表）；
/// dataType 整型码表必填（UC-0431① 播种器唯一采集源），新枚举在数组里加一项。
/// wf_*/biz_*/dev_schema_* 不在 base 范围（boot2 对应模块未建，随模块补齐再入册）
pub fn enum_registry() -> Array[@dto.DictModel] {
  [
    { name: "是否", dict_key: "yes_no", data_type: Some(2), items: [ei("是", 1), ei("否", 0)] },
    { name: "性别", dict_key: "sex", data_type: Some(2), items: [ei("男", 1), ei("女", 2), ei("未知", 3)] },
    { name: "管理员类型", dict_key: "sys_user_admin_type", data_type: Some(2), items: [ei("超级管理员", 1), ei("普通管理员", 2)] },
    { name: "角色类型", dict_key: "sys_role_role_type", data_type: Some(2), items: [ei("普通角色", 1), ei("数据角色", 2), ei("工作流", 3)] },
    {
      name: "角色数据范围",
      dict_key: "sys_role_data_scope",
      data_type: Some(2),
      items: [ei("全部数据权限", 1), ei("自定义数据权限", 2), ei("本部门数据权限", 3), ei("本部门及以下部门权限", 4), ei("仅本人数据权限", 5)],
    },
    {
      name: "菜单类型",
      dict_key: "sys_menu_type",
      data_type: Some(2),
      items: [ei("目录", 1), ei("菜单", 2), ei("按钮", 3), ei("接口", 4)],
    },
    {
      name: "菜单打开方式",
      dict_key: "sys_menu_open_type",
      data_type: Some(2),
      items: [ei("无", 0), ei("组件", 1), ei("内部链接", 2), ei("外部链接", 3)],
    },
    { name: "应用编码类型", dict_key: "sys_menu_app_code", data_type: Some(2), items: [ei("平台", 10)] },
    { name: "字典数据类型", dict_key: "sys_dict_data_type", data_type: Some(2), items: [ei("字符串", 1), ei("整型", 2)] },
    { name: "站内消息类型", dict_key: "sys_message_msg_type", data_type: Some(2), items: [ei("待办消息", 10), ei("通知消息", 20)] },
    {
      name: "系统日志操作类型",
      dict_key: "sys_op_log_op_type",
      data_type: Some(2),
      items: [ei("登录", 0), ei("查询", 1), ei("新增", 2), ei("修改", 3), ei("删除", 4), ei("主动注销", 5)],
    },
    { name: "访问类型", dict_key: "sys_vis_log_vis_type", data_type: Some(2), items: [ei("登录", 1), ei("登出", 2)] },
    {
      name: "短信业务类型",
      dict_key: "sys_sms_biz_type",
      data_type: Some(2),
      items: [ei("注册验证码", 10), ei("登录验证码", 20), ei("重置密码", 30), ei("变更验证码", 40), ei("绑定验证码", 50), ei("通知消息", 60)],
    },
    { name: "短信发送日志状态", dict_key: "sys_sms_log_status", data_type: Some(2), items: [ei("待发送", 0), ei("成功", 1), ei("失败", 2)] },
    { name: "定时任务状态", dict_key: "sys_timer_state", data_type: Some(2), items: [ei("运行", 1), ei("停止", 2)] },
    {
      name: "第三方回调处理状态",
      dict_key: "sys_third_party_callback_handle_status",
      data_type: Some(2),
      items: [ei("未处理", 0), ei("处理成功", 1), ei("处理失败", 2)],
    },
    { name: "任务队列状态", dict_key: "sys_task_execution_queue_state", data_type: Some(2), items: [ei("未开始", 0), ei("执行中", 1), ei("执行失败-待重试", 9)] },
    {
      name: "历史归档队列状态",
      dict_key: "sys_task_execution_history_state",
      data_type: Some(2),
      items: [ei("成功", 2), ei("已取消", 3), ei("失败-终态", 9)],
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
