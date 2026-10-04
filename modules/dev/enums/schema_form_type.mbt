// 模型表单类型（boot2 SchemaFormTypeEnum 同位）——码表单一事实源
///|
pub let f_popup : @core.IntVal = { code: 1, label: "弹窗" }

///|
pub let f_drawer : @core.IntVal = { code: 2, label: "抽屉" }

///|
pub let f_new_window : @core.IntVal = { code: 3, label: "新窗口" }

///|
pub fn schema_form_type_all() -> Array[@core.IntVal] {
  [f_popup, f_drawer, f_new_window]
}
