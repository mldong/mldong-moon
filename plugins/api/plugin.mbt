// 插件声明 API（v0，只够装载器用）—— 契约尽量小、尽量笨；
// 能力端口等第一个官方插件（门户注册）的调用点反推，勿提前长。
// 承重前提与判据：全部本机真库/真编译探针实证，依据随注释就近给出。

///|
/// 一条 migration = 一条语句（驱动硬约束：多语句被服务端拒且零半执行），
/// 字面量 SQL、无占位符（参数化是客户端插值，DDL 不带参数）；
/// 表名只写业务后缀，`p_<name>_` 前缀由装载器拼（归属闸拼名，构造性不可能写错）。
pub(all) struct MigrationDecl {
  version : Int // 组内单调递增，从 1 起
  ddl : String
}

///|
pub(all) struct RouteDecl {
  http_method : String // "POST" / "GET"（MoonBit 保留字 method 不能作字段名，10-06 编译现读）
  path : String // 必须以 "/plugin/<name>/" 开头（装载器校验）
  perms : Array[String] // 空 = 装载期用 derive_perm 现场算成显式 rule（主仓 by_convention=false）
  public : Bool // true = 进 exempt 面（免登录）
}

///|
/// 菜单声明：code 同时是幂等 upsert 键；parent 用父菜单 code 引用，禁数字 id
///（数字 id 跨库不可移植，重装/换库即断链）；force=false（默认）时
/// title/icon/order 等展示字段以库里现值为准（用户改动保护）。
pub(all) struct MenuDecl {
  code : String
  title : String
  parent : String
  path : String
  component : String
  icon : String
  order : Int
  btns : Array[String] // 按钮权限码
  force : Bool // 语义同原 override；MoonBit 保留字 override 不能作字段名（10-06 编译现读）
}

///|
/// 字典声明（sys_dict + sys_dict_item 两件套，字段随 sys 现状取 upsert 面）；code 是幂等键。
pub(all) struct DictItemDecl {
  code : String
  name : String
  sort : Int
}

///|
pub(all) struct DictDecl {
  code : String
  name : String
  group_code : String
  items : Array[DictItemDecl]
}

///|
/// 插件描述符 —— 趟一纯数据（无反射 ⇒ 声明必须是数据）；
/// name 必须 == 包名尾段 == 路由前缀段 == 表命名空间段（四处逐字相等）。
pub(all) struct PluginDescriptor {
  name : String
  plugin_version : String
  spec_version : Int // 契约号，装载期比对，不匹配拒绝启动
  requires : Array[String] // 依赖的能力包，装载期真校验（有字段就必须真校验，占位不读的字段不如没有）
  tables : Array[String] // 只写业务后缀（"registration"），装载器拼成 p_<name>_registration
  migrations : Array[MigrationDecl]
  routes : Array[RouteDecl]
  menus : Array[MenuDecl]
  dicts : Array[DictDecl]
}

///|
/// 命名空间绑定执行器端口（plugin-host 的 ScopedDb 实现）：
/// 表名一律只写业务后缀，实现焊死 `p_<name>_` 前缀并过 framework/collision 归属闸；
/// 实现自带串行闸（裸 Conn 并发 = 不可捕获的 wasm trap——这层是可用性防护不是风格）。
/// 注意：没有 begin/commit/rollback —— 事务边界归装载器独占（事务里二次 BEGIN
/// 会隐式提交前段，插件自己开事务等于拆装载器的台）。
pub(open) trait PluginDb {
  async fn select(
    self : Self,
    table : String,
    cols : Array[String],
    w : @core.Wrapper,
  ) -> Array[@moondb.Row] raise @core.MldongError

  async fn insert(
    self : Self,
    table : String,
    pairs : Array[@core.SetPair],
  ) -> @moondb.ExecResult raise @core.MldongError

  async fn update(
    self : Self,
    table : String,
    pairs : Array[@core.SetPair],
    w : @core.Wrapper,
  ) -> @moondb.ExecResult raise @core.MldongError

  async fn delete(
    self : Self,
    table : String,
    w : @core.Wrapper,
  ) -> @moondb.ExecResult raise @core.MldongError

  /// 逃生通道：完整 SQL 透传（复杂 JOIN 用）；实现记越界嫌疑＋启动日志点名——能用但不隐身。
  async fn exec_raw(self : Self, sql : String) -> @moondb.ExecResult raise @core.MldongError
}

///|
/// 路由注册口（装载器实现）：method+path 必须命中 descriptor 里本插件声明的路由，
/// path 以 /plugin/<name>/ 开头由装载器校验。
pub(open) trait PluginRoutes {
  fn route(
    self : Self,
    http_method : String,
    path : String,
    handler : @mb.Handler,
  ) -> Unit raise @core.MldongError
}

///|
/// 装载器发给插件的运行面 —— 只放装载器要用的最小面，能力端口留给官方插件轮次。
/// ctx：装载期恒为 @core.Ctx::system()（与模块装配期取数同惯例）；请求期主体由插件
/// handler 里自取（ctx_of 依赖 core-web，插件自理——契约不背 web 依赖）。
pub(all) struct PluginContext {
  ctx : @core.Ctx
  db : &PluginDb
  routes : &PluginRoutes
}

///|
/// 插件 trait —— 方法首参必须显式写 self（否则 &Trait 对象禁用）。
/// 钩子两条硬规矩：①必须幂等——on_enable 每次启动都跑，一次性建表/补数据
/// 属于 migration 不许塞这里；②只碰自己的资源（表命名空间 + 自己的注册中心槽位），
/// 不许改框架表、不许挂中间件（App 全局作用域）。install/uninstall 归装载器独占。
pub(open) trait Plugin {
  fn descriptor(self : Self) -> PluginDescriptor // 趟一：纯数据，不碰运行时对象
  async fn initialize(self : Self, ctx : PluginContext) -> Unit raise // 趟二：注册路由
  fn on_enable(self : Self, ctx : PluginContext) -> Unit // 钩子（owner 已拍：只开这两个）
  async fn on_disable(self : Self, ctx : PluginContext) -> Unit raise
}
