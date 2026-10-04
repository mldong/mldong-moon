// 数据表类型（boot2 SchemaTableTypeEnum 同位）——码表单一事实源：
// 业务比对用常量（.code），字典清单从 all 派生（UC-0431 播种器采集源）
///|
pub let t_single : @core.IntVal = { code: 1, label: "单表" }

///|
pub let t_primary : @core.IntVal = { code: 2, label: "主表" }

///|
pub let t_sub : @core.IntVal = { code: 3, label: "附表" }

///|
pub let t_wf : @core.IntVal = { code: 4, label: "工作流表单" }

///|
pub fn schema_table_type_all() -> Array[@core.IntVal] {
  [t_single, t_primary, t_sub, t_wf]
}
