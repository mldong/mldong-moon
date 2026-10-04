// sys_config 二次开发扩展（dao 侧）—— PUBLIC 前缀公开配置查询。
// 生成器产物之外的手写扩展面，重生成不覆盖。
// boot2 走 ConstantContext 进程内缓存（save/update 后刷新）；骨架直查库（单机等价语义），
// 缓存优化留 TODO（多实例时再引）。

///|
/// PUBLIC 前缀且启用的配置（like_pat 原样通配：前缀匹配 PUBLIC%）
pub async fn ConfigMysqlDao::list_public(self : ConfigMysqlDao) -> Array[@entity.Config] raise @core.MldongError {
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
