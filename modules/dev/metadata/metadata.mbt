// 库元数据抽象 —— gen 代码生成器与 dev_schema 导入表信息共用的底座。
// 端口零 ORM 零 web（对齐 dao 层规则）：实现方各自翻译自家目录的方言
// （MySQL=information_schema、SQLite=PRAGMA、PostgreSQL=information_schema），
// 消费方（gen/dev_schema）只认本文件的形状，换库不动消费方。

///|
/// 表元数据
pub(all) struct TableMeta {
  /// 表名
  name : String
  /// 表注释
  comment : String
}

///|
/// 列元数据
pub(all) struct ColumnMeta {
  /// 列名（snake_case）
  name : String
  /// 原始类型名（varchar/bigint/tinyint/datetime…，方言各自的叫法）
  data_type : String
  /// 完整列类型（varchar(64)/bigint(20) unsigned…）
  column_type : String
  /// YES/NO
  is_nullable : String
  /// 列默认值（None = NULL）
  default_value : String?
  /// 列注释
  comment : String
  /// 主键列
  is_pk : Bool
  /// 额外标记（MySQL: auto_increment 等）
  extra : String
}

///|
/// 元数据仓储端口 —— 实现方 = 各数据库一个 metadata-mysql / metadata-sqlite …
pub(open) trait MetadataDao {
  /// 表清单（keywords 子串过滤表名/注释，可空）
  async fn list_tables(Self, String) -> Array[TableMeta] raise @core.MldongError
  /// 列清单（ordinal 序）
  async fn list_columns(Self, String) -> Array[ColumnMeta] raise @core.MldongError
}

///|
/// 列类型 → MoonBit 实体字段类型（gen 代码生成器的映射表，mldong 框架同位）。
/// 骨架口径：时间一律 String（entity 的 create_time 同物）；数值整数 Int / Int64；
/// 其余一律 String 兜底。
pub fn column_to_field_type(c : ColumnMeta) -> String {
  let t = c.data_type
  if t == "bigint" {
    "Int64"
  } else if t == "int" || t == "smallint" || t == "mediumint" || t == "tinyint" {
    "Int"
  } else if t == "double" || t == "float" || t == "decimal" {
    "Double"
  } else {
    // varchar/char/text 系 + datetime/timestamp/date/time + 未知类型全落 String
    "String"
  }
}

///|
/// 列 → 可空（is_nullable=YES）
pub fn column_is_nullable(c : ColumnMeta) -> Bool {
  c.is_nullable == "YES"
}
