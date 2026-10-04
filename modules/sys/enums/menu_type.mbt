// 菜单类型（boot2 MenuTypeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let menu_dir : @core.IntVal = { code: 1, label: "目录" }

///|
pub let menu_item : @core.IntVal = { code: 2, label: "菜单" }

///|
pub let menu_button : @core.IntVal = { code: 3, label: "按钮" }

///|
pub let menu_interface : @core.IntVal = { code: 4, label: "接口" }

///|
pub fn menu_type_all() -> Array[@core.IntVal] {
  [menu_dir, menu_item, menu_button, menu_interface]
}
