// 模型字段类型（boot2 SchemaFieldDataTypeEnum 同位）——码表单一事实源；
// code 9..28/30..33（29 byte[] 注释掉，与 boot2 一致）；该字典 dataType=1 字符串码
// （boot2 getDataType()=String.class 同位），dev_schema_field.data_type 列存的就是这些 code 串
///|
pub let dt_byte : @core.IntVal = { code: 9, label: "Byte" }

///|
pub let dt_short : @core.IntVal = { code: 10, label: "Short" }

///|
pub let dt_character : @core.IntVal = { code: 11, label: "Character" }

///|
pub let dt_integer : @core.IntVal = { code: 12, label: "Integer" }

///|
pub let dt_long : @core.IntVal = { code: 13, label: "Long" }

///|
pub let dt_float : @core.IntVal = { code: 14, label: "Float" }

///|
pub let dt_double : @core.IntVal = { code: 15, label: "Double" }

///|
pub let dt_boolean : @core.IntVal = { code: 16, label: "Boolean" }

///|
pub let dt_string : @core.IntVal = { code: 17, label: "String" }

///|
pub let dt_date_sql : @core.IntVal = { code: 18, label: "Date" }

///|
pub let dt_time : @core.IntVal = { code: 19, label: "Time" }

///|
pub let dt_timestamp : @core.IntVal = { code: 20, label: "Timestamp" }

///|
pub let dt_blob : @core.IntVal = { code: 21, label: "Blob" }

///|
pub let dt_clob : @core.IntVal = { code: 22, label: "Clob" }

///|
pub let dt_local_date : @core.IntVal = { code: 23, label: "LocalDate" }

///|
pub let dt_local_time : @core.IntVal = { code: 24, label: "LocalTime" }

///|
pub let dt_year : @core.IntVal = { code: 25, label: "Year" }

///|
pub let dt_year_month : @core.IntVal = { code: 26, label: "YearMonth" }

///|
pub let dt_local_dt : @core.IntVal = { code: 27, label: "LocalDateTime" }

///|
pub let dt_instant : @core.IntVal = { code: 28, label: "Instant" }

///|
pub let dt_object : @core.IntVal = { code: 30, label: "Object" }

///|
pub let dt_date : @core.IntVal = { code: 31, label: "Date" }

///|
pub let dt_big_integer : @core.IntVal = { code: 32, label: "BigInteger" }

///|
pub let dt_big_decimal : @core.IntVal = { code: 33, label: "BigDecimal" }

///|
pub fn schema_field_data_type_all() -> Array[@core.IntVal] {
  [
    dt_byte, dt_short, dt_character, dt_integer, dt_long, dt_float, dt_double,
    dt_boolean, dt_string, dt_date_sql, dt_time, dt_timestamp, dt_blob, dt_clob,
    dt_local_date, dt_local_time, dt_year, dt_year_month, dt_local_dt, dt_instant,
    dt_object, dt_date, dt_big_integer, dt_big_decimal,
  ]
}
