// 装载器给插件发运行面 —— PluginContext 组装（卡 5 ⑨ 的挂载机件）。
// db = ScopedDb（命名空间绑定 + 串行闸；tables=[] 的插件基本不用——jeeflow 即此类，
// 引擎自带连接管理）；routes = 调用方提供的 sink（cmd/main 经 guard 挂 moonback）；
// ctx = system Ctx（装载期惯例）。连接随 ScopedDb 存活（每插件一条，装载后空闲持有）。

///|
pub async fn plugin_context(
  config : @core.MysqlConfig,
  d : @api.PluginDescriptor,
  routes : &@api.PluginRoutes,
  sys_query : &@api.SysQueryApi,
  dev_query : &@api.DevQueryApi,
  dicts : &@api.PluginDictApi,
  messages : &@api.PluginMessageApi,
) -> @api.PluginContext raise @core.MldongError {
  let conn = @repo.open_conn(config)
  let db : &@api.PluginDb = plugin_db_of(conn, d.name, d.tables)
  { ctx: @core.Ctx::system(), db, routes, sys_query, dev_query, dicts, messages }
}
