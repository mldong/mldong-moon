// 字段配置智能推断 —— boot2 SchemaFieldInferUtil 逐规则 port + goframe schema_field_infer.go
// 的 SQL 类型映射（moon 直读 information_schema）与
// UC-0309 增补（备注语义 Textarea 优先 / 日期数字列可排序 / columnWidth 默认列宽）。
// 纯函数零 IO——moon test 直跑（单测在 service/schema_field_infer_test.mbt）。

///|
/// SQL 类型名 → 模型字段类型枚举 code（boot2 SchemaFieldDataTypeEnum 码表；
/// goframe sqlTypeToEnumCode 同表 port：text 系→Clob、tinyint(1)→Boolean）
pub fn sql_type_to_enum_code(data_type : String, size : Int) -> Int {
  let text_like = data_type == "text" ||
    data_type == "mediumtext" ||
    data_type == "longtext" ||
    data_type == "tinytext"
  if data_type == "varchar" || data_type == "char" || data_type == "enum" || data_type == "set" || data_type == "json" {
    return @enums.dt_string.code
  }
  if text_like {
    return @enums.dt_clob.code
  }
  if data_type == "int" || data_type == "integer" || data_type == "mediumint" {
    return @enums.dt_integer.code
  }
  if data_type == "tinyint" {
    if size <= 1 {
      return @enums.dt_boolean.code
    }
    return @enums.dt_integer.code
  }
  if data_type == "smallint" {
    return @enums.dt_short.code
  }
  if data_type == "bigint" {
    return @enums.dt_long.code
  }
  if data_type == "decimal" || data_type == "numeric" {
    return @enums.dt_big_decimal.code
  }
  if data_type == "double" {
    return @enums.dt_double.code
  }
  if data_type == "float" {
    return @enums.dt_float.code
  }
  if data_type == "bit" {
    return @enums.dt_boolean.code
  }
  if data_type == "datetime" {
    return @enums.dt_local_dt.code
  }
  if data_type == "timestamp" {
    return @enums.dt_timestamp.code
  }
  if data_type == "date" {
    return @enums.dt_local_date.code
  }
  if data_type == "time" {
    return @enums.dt_time.code
  }
  if data_type == "year" {
    return @enums.dt_year.code
  }
  if data_type == "blob" ||
    data_type == "longblob" ||
    data_type == "mediumblob" ||
    data_type == "tinyblob" ||
    data_type == "binary" ||
    data_type == "varbinary" {
    return @enums.dt_blob.code
  }
  @enums.dt_string.code
}

///|
/// 推断表单组件（boot2 inferComponent 同序：id 早支在 infer_field_ext 之外单独处理）
pub fn infer_component(code : Int, field_name : String, field_size : Int) -> String {
  if code == @enums.dt_string.code {
    // 备注/说明字段语义稳定，优先 Textarea（UC-0309 第 7 条）
    if field_name.contains("remark") ||
      field_name.contains("reason") ||
      field_name.contains("description") ||
      field_name.contains("comment") {
      return "Textarea"
    }
    if field_size > 200 {
      return "Textarea"
    }
    return "Input"
  }
  if code == @enums.dt_clob.code {
    return "Textarea"
  }
  if code == @enums.dt_integer.code ||
    code == @enums.dt_long.code ||
    code == @enums.dt_short.code ||
    code == @enums.dt_byte.code ||
    code == @enums.dt_big_integer.code {
    if field_name.contains("process_instance") {
      return "TableLink"
    }
    if field_name.has_suffix("_id") {
      if field_name.contains("dept") {
        return "ApiTreeSelect"
      }
      return "ApiSelect"
    }
    if field_name.contains("status") || field_name.contains("type") || field_name.contains("flag") {
      return "ApiDict"
    }
    return "InputNumber"
  }
  if code == @enums.dt_big_decimal.code ||
    code == @enums.dt_float.code ||
    code == @enums.dt_double.code {
    return "InputNumber"
  }
  if code == @enums.dt_boolean.code {
    return "ApiDict"
  }
  if code == @enums.dt_local_date.code ||
    code == @enums.dt_date_sql.code ||
    code == @enums.dt_date.code ||
    code == @enums.dt_local_dt.code ||
    code == @enums.dt_timestamp.code ||
    code == @enums.dt_local_time.code ||
    code == @enums.dt_year.code ||
    code == @enums.dt_year_month.code ||
    code == @enums.dt_instant.code ||
    code == @enums.dt_time.code {
    return "DatePicker"
  }
  // 特殊字段名推断（图片/文件；boot2 落在类型分支未命中之后）
  if field_name.contains("image") ||
    field_name.contains("icon") ||
    field_name.contains("avatar") ||
    field_name.contains("logo") ||
    field_name.contains("file") ||
    field_name.contains("attachment") ||
    field_name.contains("document") {
    return "Upload"
  }
  "Input"
}

///|
/// 主键/id 字段 ext（boot2 早支：buildExt 默认 0 值 + list/view 隐藏 + hidden；
/// 不设 addHide/editHide——前端生成器靠 dependencies.show=false 藏 id，编辑回填 id 必需）
pub fn infer_id_ext() -> Json {
  {
    "addHide": Json::number(0),
    "editHide": Json::number(0),
    "listHide": Json::number(1),
    "viewHide": Json::number(1),
    "required": Json::number(0),
    "search": Json::number(0),
    "Input_type": Json::string("hidden"),
  }
}

///|
/// 推断字段 ext（boot2 inferExt 骨架 + goframe UC-0309 增补；返回完整对象落 variable 列）
pub fn infer_field_ext(
  code : Int,
  field_name : String,
  _field_size : Int,
  component : String,
  table_name : String,
) -> Json {
  // buildExt 默认 0 值（boot2）
  let obj : Map[String, Json] = {
    "addHide": Json::number(0),
    "editHide": Json::number(0),
    "listHide": Json::number(0),
    "viewHide": Json::number(0),
    "required": Json::number(0),
    "search": Json::number(0),
  }
  // 必填推断（boot2 nullableToRequired：名称类字段）
  if field_name.contains("name") || field_name.contains("title") || field_name.contains("code") {
    let _ = obj.set("required", Json::number(1))
  }
  match component {
    "ApiSelect" => {
      // 关联表 API（boot2 extractRelationTable 常见映射 + goframe 同表）
      let relation = relation_table_of(field_name)
      if !relation.is_empty() {
        let _ = obj.set("ApiSelect_api", Json::string("/\{relation}/select"))
        let _ = obj.set("ApiSelect_immediate", Json::boolean(true))
      }
      let _ = obj.set("searchType", Json::string("IN"))
    }
    "ApiTreeSelect" => {
      if field_name.contains("dept") {
        let _ = obj.set("ApiTreeSelect_api", Json::string("/sys/dept/tree"))
        let _ = obj.set("ApiTreeSelect_immediate", Json::boolean(true))
      }
      let _ = obj.set("searchType", Json::string("IN"))
    }
    "ApiDict" => {
      let _ = obj.set("searchType", Json::string("IN"))
      if code == @enums.dt_boolean.code {
        let _ = obj.set("ApiDict_code", Json::string("yes_no"))
        let _ = obj.set("ApiDict_renderType", Json::string("RadioGroup"))
        let _ = obj.set("ApiDict_isBtn", Json::boolean(true))
      } else {
        // 字典 code = {tableName}_{fieldName}（boot2 extractDictCode：_type/_status/_flag 后缀）
        if field_name.has_suffix("_type") ||
          field_name.has_suffix("_status") ||
          field_name.has_suffix("_flag") {
          let dict_code = if table_name.is_empty() {
            field_name
          } else {
            "\{table_name}_\{field_name}"
          }
          let _ = obj.set("ApiDict_code", Json::string(dict_code))
          let _ = obj.set("ApiDict_renderType", Json::string("Select"))
        }
      }
    }
    "TableLink" => {
      // 流程实例链接——仅列表/详情可见
      let _ = obj.set("addHide", Json::number(1))
      let _ = obj.set("editHide", Json::number(1))
    }
    "DatePicker" => {
      let fmt = if code == @enums.dt_local_date.code ||
        code == @enums.dt_date_sql.code ||
        code == @enums.dt_date.code {
        "YYYY-MM-DD"
      } else {
        "YYYY-MM-DD HH:mm:ss"
      }
      let _ = obj.set("DatePicker_valueFormat", Json::string(fmt))
      let _ = obj.set("DatePicker_format", Json::string(fmt))
      let _ = obj.set("searchType", Json::string("EQ"))
    }
    "Upload" => {
      if field_name.contains("image") ||
        field_name.contains("icon") ||
        field_name.contains("avatar") {
        let _ = obj.set("Upload_maxSize", Json::number(2))
        let _ = obj.set("Upload_multiple", Json::boolean(false))
        let _ = obj.set("Upload_listType", Json::string("picture-card"))
      } else {
        let _ = obj.set("Upload_maxSize", Json::number(10))
        let _ = obj.set("Upload_multiple", Json::boolean(true))
        let _ = obj.set("Upload_listType", Json::string("text"))
      }
    }
    "InputNumber" => {
      let _ = obj.set("min", Json::number(0))
      let _ = obj.set("searchType", Json::string("EQ"))
    }
    "Input" => {
      // 短文本 LIKE（boot2 inferSearchType：Input+STRING）
      if code == @enums.dt_string.code {
        let _ = obj.set("searchType", Json::string("LIKE"))
      }
    }
    _ => ()
  }
  // searchType 有值才置 search=1（boot2：searchType != null 才写 search+searchType）
  match obj.get("searchType") {
    Some(_) => { let _ = obj.set("search", Json::number(1)) }
    None => ()
  }
  // UC-0309 增补：日期/数字列默认可排序
  if component == "DatePicker" || component == "InputNumber" {
    let _ = obj.set("sort", Json::number(1))
  }
  // UC-0309 增补：默认列宽（避免所有列等宽）
  let width = match component {
    "DatePicker" => 150
    "ApiSelect" => 120
    "ApiTreeSelect" => 120
    "Textarea" => 200
    _ => 100
  }
  let _ = obj.set("columnWidth", Json::number(width.to_double()))
  Json::object(obj)
}

///|
/// 完整推断一行字段配置（boot2 inferFieldConfig 入口）：
/// 主键/id 早支 → component + ext 落地；返回 (component, variable_json)
pub fn infer_field_config(
  is_primary : Bool,
  field_name : String,
  data_type_code : Int,
  field_size : Int,
  table_name : String,
) -> (String, String) {
  if field_name == "id" || is_primary {
    return ("Input", infer_id_ext().stringify())
  }
  let component = infer_component(data_type_code, field_name, field_size)
  let ext = infer_field_ext(data_type_code, field_name, field_size, component, table_name)
  (component, ext.stringify())
}

///|
/// 从字段名提取关联表（boot2 extractRelationTable 常见映射：user_id → sys/user）
fn relation_table_of(field_name : String) -> String {
  if !field_name.has_suffix("_id") {
    return ""
  }
  let prefix = field_name[:field_name.length() - 3].to_owned()
  match prefix {
    "user" | "userId" => "sys/user"
    "dept" | "deptId" => "sys/dept"
    "role" | "roleId" => "sys/role"
    "dict" | "dictId" => "sys/dict"
    "file" | "fileId" => "sys/file"
    _ => prefix
  }
}

///|
/// 拖拽排序换位算法（boot2 SchemaFieldServiceImpl#updateSort 逐行 port）：
/// 拖拽行取 hover 行 sort；hover 行让位（往上拖 +1 / 往下拖 -1）；
/// hover 前后区间的其余行整体 ±1。返回 (id, new_sort) 更新清单（无操作返回空）。
pub fn drag_sort_plan(
  ids : Array[Int64],
  sorts : Array[Int64],
  drag_row_id : Int64,
  hover_row_id : Int64,
) -> Array[(Int64, Int64)] {
  let plan : Array[(Int64, Int64)] = []
  if ids.is_empty() || drag_row_id == hover_row_id {
    return plan
  }
  let n = ids.length()
  let mut drag_idx = 0
  let mut hover_idx = 0
  for i in 0..<n {
    if ids[i] == drag_row_id {
      drag_idx = i
    }
    if ids[i] == hover_row_id {
      hover_idx = i
    }
  }
  let hover_sort = sorts[hover_idx]
  // 先更新拖拽行
  plan.push((drag_row_id, hover_sort))
  // hover 行让位
  if drag_idx > hover_idx {
    plan.push((hover_row_id, hover_sort + 1L))
  } else if drag_idx < hover_idx {
    plan.push((hover_row_id, hover_sort - 1L))
  }
  // 其余行（hover 相邻区间）整体 ±1
  for i in 0..<n {
    if i < hover_idx && ids[i] != drag_row_id && ids[i] != hover_row_id {
      plan.push((ids[i], sorts[i] - 1L))
    } else if i > hover_idx && ids[i] != drag_row_id && ids[i] != hover_row_id {
      plan.push((ids[i], sorts[i] + 1L))
    }
  }
  plan
}
