// DevQueryApi 实现 —— api 层（与 SysQueryApiImpl/SysMessageApiImpl 同一姿势：委托既有实现，
// 不在本层写 SQL）。取名 Dev*（dev/低代码那一族动态表的查询面）而实现落在 sys，是因为
// 动态表网关的真身是 modules/sys/repository/generic_query.mbt 的 GenericDao
// （lowCode/{table}/page|detail 那两条端点用的就是它）；跨模块只能经 service 口，
// 而这条口本就是 sys 的基础设施，不另起一份 information_schema 轮子。
// 消费点＝jeeflow 插件的 persist 装配（业务表元数据 + bizData 回显）。

///|
pub struct DevQueryApiImpl {
  dao : @repo.GenericDao
}

///|
pub fn DevQueryApiImpl::make(config : @core.MysqlConfig) -> DevQueryApiImpl {
  { dao: @repo.GenericDao::make(config) }
}

///|
pub impl @api.DevQueryApi for DevQueryApiImpl with fn table_columns(
  self,
  table : String,
) -> Array[@api.DevColumnMeta] raise @core.MldongError {
  let cols = self.dao.table_columns(table)
  let out : Array[@api.DevColumnMeta] = []
  for name, dtype in cols {
    out.push({ name, data_type: dtype })
  }
  out
}

///|
pub impl @api.DevQueryApi for DevQueryApiImpl with fn row_by_column(
  self,
  table : String,
  column : String,
  value : Int64,
) -> Option[Map[String, Json]] raise @core.MldongError {
  match self.dao.row_by_column(table, column, value) {
    Some(json) =>
      match json {
        Json::Object(row) => Some(row)
        _ => None
      }
    None => None
  }
}

///|
pub extend DevQueryApiImpl with @api.DevQueryApi::{row_by_column, table_columns}
