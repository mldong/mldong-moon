// dev 元数据出参装配 —— 对齐 boot2 dev/schema 的形状

///|
/// 表清单项（boot2 dbTable → [{name, comment}]；disabled 待 dev_schema 台账落地后补）
pub fn table_meta_json(t : @meta.TableMeta) -> Json {
  { "name": t.name, "comment": t.comment }
}

///|
/// 列清单项（信息模式原始形状 + 映射后的实体字段类型，gen/导入两用）
pub fn column_meta_json(c : @meta.ColumnMeta) -> Json {
  {
    "name": c.name,
    "dataType": c.data_type,
    "columnType": c.column_type,
    "isNullable": Json::string(c.is_nullable),
    "defaultValue": match c.default_value {
      Some(v) => Json::string(v)
      None => Json::null()
    },
    "comment": c.comment,
    "isPk": Json::boolean(c.is_pk),
    "extra": c.extra,
    // gen 代码生成器的映射产物（column_to_field_type）
    "fieldType": Json::string(@meta.column_to_field_type(c)),
    "option": Json::boolean(@meta.column_is_nullable(c)),
  }
}
