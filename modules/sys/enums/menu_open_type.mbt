// 菜单打开方式（boot2 MenuOpenTypeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let open_none : @core.IntVal = { code: 0, label: "无" }

///|
pub let open_component : @core.IntVal = { code: 1, label: "组件" }

///|
pub let open_iframe : @core.IntVal = { code: 2, label: "内部链接" }

///|
pub let open_link : @core.IntVal = { code: 3, label: "外部链接" }

///|
pub fn menu_open_type_all() -> Array[@core.IntVal] {
  [open_none, open_component, open_iframe, open_link]
}
