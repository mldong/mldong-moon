// dev 域枚举字典聚合注册（goframe utility/GetEnums 同位）：
// 一行一个枚举（label 同名同 key 同码表，见各枚举文件）；新枚举 = 新文件 + 此处一行。
// 注意 schema_field_data_type 是字符串码字典（dataType=1，boot2 getDataType()=String.class），
// 走 int_dict_as；其余整型码走 int_dict（dataType=2）

///|
pub fn dev_enum_dicts() -> Array[@core.DictModel] {
  [
    @core.int_dict("数据表类型", "dev_schema_table_type", schema_table_type_all()),
    @core.int_dict("模型表单类型", "dev_schema_form_type", schema_form_type_all()),
    @core.int_dict("模型字段存储类型", "dev_schema_field_storage_type", schema_field_storage_type_all()),
    @core.int_dict_as(
      "模型字段类型",
      "dev_schema_field_data_type",
      1,
      schema_field_data_type_all(),
    ),
  ]
}

///|
/// 装配期注册（goframe init() 的 moon 同位：模块 install 里灌注册中心）
pub fn register_dev_enum_dicts(registry : @core.EnumDictRegistry) -> Unit {
  for m in dev_enum_dicts() {
    registry.register(m)
  }
}
