// 访问类型（boot2 VisTypeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let vis_login : @core.IntVal = { code: 1, label: "登录" }

///|
pub let vis_logout : @core.IntVal = { code: 2, label: "登出" }

///|
pub fn vis_type_all() -> Array[@core.IntVal] {
  [vis_login, vis_logout]
}
