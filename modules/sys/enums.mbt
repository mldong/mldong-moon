// sys 模块枚举字典声明 —— boot2 @DictEnum 的 sys 域 + 基础件逐项对齐（18 个，
// 同 key 同名同码表，dataType 全 2 整型码）；goframe「每枚举一文件 + init() 注册」的
// moon 同位 = 本文件声明 + 模块装配期 register_sys_enum_dicts 灌入注册中心。
// wf_*/biz_*/dev_schema_*（12 键）不在 base 范围——对应模块建时各写各的 enums.mbt。

///|
/// 枚举字典项速记（label=枚举 message、value=枚举 code；dataType 全 2 整型码）
fn ei(label : String, value : Int) -> @core.DictItemModel {
  {
    name: label,
    dict_item_value: Json::number(value.to_double()),
    dict_item_key: value.to_string(),
    ext: None,
  }
}

///|
/// sys 域枚举字典声明（boot2 @DictEnum 盘点快照；新枚举在数组里加一项）
pub fn sys_enum_dicts() -> Array[@core.DictModel] {
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
/// 装配期注册（goframe init() 的 moon 同位：模块 install 里显式灌注册中心）
pub fn register_sys_enum_dicts(registry : @core.EnumDictRegistry) -> Unit {
  for m in sys_enum_dicts() {
    registry.register(m)
  }
}
