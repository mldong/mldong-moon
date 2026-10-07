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
/// sys 查询面 · 契约 DTO —— 面向完整业务投影（不按单个消费方裁字段；后来者同样要用户信息）。
/// 字段面 = sys_user/sys_dept/sys_post 实体全量 + 关联名（dept/post 名称编码）。
pub(all) struct SysUserDetail {
  id : Int64
  user_name : String
  real_name : String
  nick_name : String?
  mobile_phone : String?
  email : String?
  sex : Int?
  admin_type : Int?
  is_locked : Int?
  dept_id : Int64?
  dept_name : String?
  dept_code : String?
  post_id : Int64?
  post_name : String?
  post_code : String?
  remark : String?
}

///|
pub(all) struct SysDeptDetail {
  id : Int64
  name : String
  code : String
  parent_id : Int64?
  leader_ids : Array[String] // 库内逗号串已拆
  main_leader_id : Int64?
  sort : Int64?
}

///|
pub(all) struct SysPostDetail {
  id : Int64
  name : String
  code : String
  sort : Int64?
}

///|
pub(all) struct SysUserPage {
  rows : Array[SysUserDetail]
  record_count : Int
}

///|
/// 用户页查询条件（keywords = user_name/real_name 模糊；结构化字段随需增量，先不搬全量 m_ 操作符）
pub(all) struct SysUserQuery {
  page : Int
  size : Int
  keywords : String
}

///|
/// 角色-用户对（角色编码 → 在册用户 id 集；引擎按角色找人节点的预载数据）
pub(all) struct SysRoleUser {
  role_code : String
  user_id : String
}

///|
/// sys 查询面 —— 插件可调用的框架查询能力（依赖倒置：契约在此，实现归框架层
/// modules/sys 的 api 层——委托 service，等同 boot4 的 mldong-sys-api UserApi/DeptApi 层；
/// cmd/main 注册插件时注入 PluginContext；插件禁止依赖框架实现模块）。
/// 方法面 = 用户/部门/岗位/角色完整查询业务面（不按单个消费方裁剪）；写面按真实调用点另立。
/// 方法全 async/live——引擎同步 SPI 的新鲜度妥协由消费插件预载承担（v2 引擎 SPI 异步化后消亡）。
pub(open) trait SysQueryApi {
  /// 用户：按 id 取完整投影（含部门/岗位关联名）；不存在返回 None
  async fn user_by_id(
    self : Self,
    id : Int64,
  ) -> Option[SysUserDetail] raise @core.MldongError

  /// 用户：分页（keywords 对 user_name/real_name 模糊）
  async fn user_page(self : Self, q : SysUserQuery) -> SysUserPage raise @core.MldongError

  /// 用户：全量轻量（未删除；部门用户树/快照预载用）
  async fn user_list(self : Self) -> Array[SysUserDetail] raise @core.MldongError

  /// 部门：按 id；不存在返回 None
  async fn dept_by_id(
    self : Self,
    id : Int64,
  ) -> Option[SysDeptDetail] raise @core.MldongError

  /// 部门：全量在册（小表；快照预载用）
  async fn dept_list(self : Self) -> Array[SysDeptDetail] raise @core.MldongError

  /// 岗位：全量在册（小表）
  async fn post_list(self : Self) -> Array[SysPostDetail] raise @core.MldongError

  /// 角色：全量角色-用户对（角色找人节点的预载数据）
  async fn role_user_pairs(self : Self) -> Array[SysRoleUser] raise @core.MldongError
}

///|
/// 装载器发给插件的运行面 —— 只放装载器要用的最小面，能力端口留给官方插件轮次。
/// ctx：装载期恒为 @core.Ctx::system()（与模块装配期取数同惯例）；请求期主体由插件
/// handler 里自取（ctx_of 依赖 core-web，插件自理——契约不背 web 依赖）。
pub(all) struct PluginContext {
  ctx : @core.Ctx
  db : &PluginDb
  routes : &PluginRoutes
  sys_query : &SysQueryApi // 框架查询面（v1：jeeflow 供数；新能力以增量方法/新接口扩展）
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
