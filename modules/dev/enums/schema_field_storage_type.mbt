// 模型字段存储类型（boot2 SchemaFieldStorageTypeEnum 同位）——码表单一事实源；
// 实体暂无对应列（boot2 亦预留），随关联表功能落地再消费
///|
pub let st_normal : @core.IntVal = { code: 1, label: "普通字段" }

///|
pub let st_expand : @core.IntVal = { code: 2, label: "对象展开到主表" }

///|
pub let st_json : @core.IntVal = { code: 3, label: "JSON字符串存储" }

///|
pub let st_one2one : @core.IntVal = { code: 4, label: "一对一关联表" }

///|
pub let st_one2many : @core.IntVal = { code: 5, label: "一对多子表" }

///|
pub fn schema_field_storage_type_all() -> Array[@core.IntVal] {
  [st_normal, st_expand, st_json, st_one2one, st_one2many]
}
