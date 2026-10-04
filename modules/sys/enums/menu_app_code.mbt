// 应用编码类型（boot2 MenuAppCodeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let platform : @core.IntVal = { code: 10, label: "平台" }

///|
pub fn menu_app_code_all() -> Array[@core.IntVal] {
  [platform]
}
