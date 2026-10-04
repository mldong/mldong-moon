// sys 域枚举字典聚合注册（goframe utility/GetEnums 同位）：
// 一行一个枚举（label 同名同 key 同码表，见各枚举文件）；新枚举 = 新文件 + 此处一行

///|
pub fn sys_enum_dicts() -> Array[@core.DictModel] {
  [
    @core.int_dict("是否", "yes_no", yes_no_all()),
    @core.int_dict("性别", "sex", sex_all()),
    @core.int_dict("管理员类型", "sys_user_admin_type", admin_type_all()),
    @core.int_dict("角色类型", "sys_role_role_type", role_type_all()),
    @core.int_dict("角色数据范围", "sys_role_data_scope", role_data_scope_all()),
    @core.int_dict("菜单类型", "sys_menu_type", menu_type_all()),
    @core.int_dict("菜单打开方式", "sys_menu_open_type", menu_open_type_all()),
    @core.int_dict("应用编码类型", "sys_menu_app_code", menu_app_code_all()),
    @core.int_dict("字典数据类型", "sys_dict_data_type", dict_data_type_all()),
    @core.int_dict("站内消息类型", "sys_message_msg_type", message_type_all()),
    @core.int_dict("系统日志操作类型", "sys_op_log_op_type", op_log_type_all()),
    @core.int_dict("访问类型", "sys_vis_log_vis_type", vis_type_all()),
    @core.int_dict("短信业务类型", "sys_sms_biz_type", sms_biz_type_all()),
    @core.int_dict("短信发送日志状态", "sys_sms_log_status", sms_log_status_all()),
    @core.int_dict("定时任务状态", "sys_timer_state", timer_state_all()),
    @core.int_dict("第三方回调处理状态", "sys_third_party_callback_handle_status", third_party_callback_status_all()),
    @core.int_dict("任务队列状态", "sys_task_execution_queue_state", task_queue_state_all()),
    @core.int_dict("历史归档队列状态", "sys_task_execution_history_state", task_history_state_all()),
  ]
}

///|
/// 装配期注册（goframe init() 的 moon 同位：模块 install 里灌注册中心）
pub fn register_sys_enum_dicts(registry : @core.EnumDictRegistry) -> Unit {
  for m in sys_enum_dicts() {
    registry.register(m)
  }
}
