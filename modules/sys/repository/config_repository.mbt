// sys_config MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct ConfigRepository {
  base : BaseDao[@entity.Config]
}

///|
pub fn ConfigRepository::make(config : @core.MysqlConfig) -> ConfigRepository {
  { base: { config, table: config_table } }
}

///|
pub impl @dao.ConfigDao for ConfigRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.ConfigDao for ConfigRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.ConfigDao for ConfigRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.ConfigDao for ConfigRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.ConfigDao for ConfigRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.ConfigDao for ConfigRepository with fn check_unique(
  self,
  code,
  exclude_id,
  msg,
) {
  self.base.check_unique("code", S(code), exclude_id, msg)
}

///|
pub impl @dao.ConfigDao for ConfigRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

pub extend ConfigRepository with @dao.ConfigDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
}

///|
/// PUBLIC 前缀且启用的配置（like_pat 原样通配：前缀匹配 PUBLIC%）——二次开发（公开配置）
pub async fn ConfigRepository::list_public(self : ConfigRepository) -> Array[@entity.Config] raise @core.MldongError {
  let (sql, params) = @core.build_select(
    "sys_config",
    self.base.table.cols,
    self.base.base_where().like_pat("code", "PUBLIC%").eq("enabled", @core.I(1)),
    orders=[("code", false)],
  )
  let out : Array[@entity.Config] = []
  for r in self.base.query(sql, params) {
    out.push((self.base.table.from_row)(r))
  }
  out
}

///|
/// 全量配置（启动灌入 holder 用；未删除范围，code 序）
pub async fn ConfigRepository::list_all(self : ConfigRepository) -> Array[@entity.Config] raise @core.MldongError {
  let out : Array[@entity.Config] = []
  for r in self.base.query(
    "SELECT " + self.base.table.cols.join(", ") + " FROM sys_config WHERE is_deleted = 0 ORDER BY code",
    [],
  ) {
    out.push((self.base.table.from_row)(r))
  }
  out
}
