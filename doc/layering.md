# 分层规范

> mldong-moon 的分层是 mldong 框架同构的：业务收 service、dao 解耦 ORM、controller 只做校验与转发。
> 本文是写代码前的必读规范；模板真身在 `modules/sys`（user 全链 + role + RBAC 中间表）。

## 1. 总览

```
controller（moonback handler：@web.wrap 包住 → dto 校验 → 转发 service → core 信封）
     │ 只调 service / rbac service
     ▼
service（业务逻辑唯一收口：trait + Impl[R]；纯规则抽纯函数；零 web / 零 ORM 类型）
     │ 只调 dao 端口
     ▼
dao（端口 trait：签名只用 entity/dto/@core.Wrapper，零 moondb/moonmysql）
     │ 实现
     ▼
repository（手写 SQL + 行映射；BaseDao[T] 模板 + TableCodec；驱动/方言收口 dialect.mbt 的 Conn 缝）

entity（纯数据 struct，零行为）      dto（入参 schema + parse_* + Req + 出参装配）
core（错误码/信封/sqlbuilder/m_ 查询/雪花/时钟——零 web）   core-web（moonback 适配——wrap/守卫工具）
```

**依赖规则（硬约束）**：

| 规则 | 理由 |
|---|---|
| `core` 不 import 任何 web/ORM 包 | 框架无关底座，模块间共享、可独立测试 |
| web 依赖（moonback）只出现在 `core-web` 与各模块 `controller` | 换 web 框架只动这两处 |
| 驱动/方言依赖只出现在各模块 `repository`（dialect.mbt 的 Conn trait + Box + 工厂） | 换库只动方言文件，BaseDao/SQL builder 不动 |
| `service` 签名零 web/ORM 类型（entity/dto/@core 进出） | 保证 service 可迁移、可纯测 |
| `dao` trait 签名零 ORM 类型，条件用 `@core.Wrapper` 进出 | "业务怎么查"由 service 组 Wrapper 说了算 |
| controller 不写业务逻辑（查重/默认值/状态机全在 service） | controller 只是"校验 + 转发" |

## 2. 六件套（每张业务表固定六层）

以 `sys_user` → `User` 为例（**类名去表前缀，文件名带层后缀**）：

| 层 | 文件 | 职责 | 禁止 |
|---|---|---|---|
| entity | `entity/user.mbt` | 纯数据 struct + 关联行 struct（如 `UserPageRow`） | 任何方法/IO |
| dto | `dto/user_dto.mbt` | moon_zod schema、`Req` struct、`parse_save/parse_update/parse_page`、出参装配 `user_json/page_row_json` | 业务逻辑 |
| dao | `dao/user_dao.mbt` | `trait UserDao`（端口） | SQL 字样 |
| repository | `repository/user_table.mbt`（TableCodec+row 映射）、`user_repository.mbt`（trait impl）、`user_page.mbt`（join 版查询） | SQL 与行映射 | 业务规则 |
| service | `service/user_service.mbt` | `trait UserService` + `UserServiceImpl[R]`：校验、查重、默认值、错误码 | web/ORM 类型 |
| controller | `controller/user_controller.mbt` | `policy()` 权限码片段（与端点同文件）+ `register()` 薄端点 | 业务逻辑 |

## 3. 各层写法要点

### 3.1 entity

- 纯 `struct`，字段与表列一一对应（snake_case 命名字段）；可空列用 `Option`；
- 雪花主键 `Int64`，**进出 JSON 一律字符串**（JS 53 位精度，同款坑统一修）；
- 关联查询（分页 join dept/post）另立只读 struct：`UserPageRow { user : User, dept_name : String?, ... }`。

### 3.2 dto（moon_zod 全工程唯一入口）

```moonbit
// ① schema：规则声明（msg= 自定义文案）
let save_schema : @moon_zod.Schema = @moon_zod.object({
  "id": @moon_zod.any().optional(),          // ⚠ strip 模式：schema 没声明的字段会被丢弃，
  "deptId": @moon_zod.any().optional(),      //   "不校验但要存活"的字段必须 any().optional() 占位
  "userName": @moon_zod.string().min(2, msg="用户名至少 2 个字符").max(32),
  ...
})

// ② parse：schema 校验 → 手工提 Req（camelCase JSON → snake_case struct 字段）
pub fn parse_save(body : Json) -> UserSaveReq raise @core.MldongError {
  match save_schema.parse(body) {
    Ok(data) => req_of(data)
    Err(errors) => raise @core.MldongError::InvalidInput(errors[0].to_string())
  }
}

// ③ 分页入参：pageNum/pageSize 自校验 + m_* 动态条件交给 core 通用件
@core.parse_m_params(body, exclude=["pageNum", "pageSize", "keywords", "searchKeys"])
```

- update 复用 save schema，`parse_update` 额外校验 `id > 0`；
- 出参装配同文件（`user_json`/`page_row_json`），雪花 id 用 `jsnow`（字符串化）、可空用 `jstr/jint`（null）。

### 3.3 dao（端口）

```moonbit
pub(open) trait UserDao {
  async fn insert(Self, @entity.User) -> Int64 raise @core.MldongError
  async fn update(Self, @entity.User) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.User? raise @core.MldongError
  async fn find_by_user_name(Self, String) -> @entity.User? raise @core.MldongError   // 业务查重
  async fn page(Self, @core.Wrapper, Int, Int) -> (Int, Array[@entity.UserPageRow]) raise @core.MldongError
}
```

- 返回 `?` 表示"不存在不是错"，由 service 决定转 `NotFound`；
- 分页统一返回 `(总数, 当页行)`，行用关联 struct。

### 3.4 repository（适配器实现）

> 命名理据：`dao`（端口）与 `repository`（适配器）在 Java 语境是**同一槽位的两个词**——
> DAO 出自 J2EE BluePrints（表/CRUD 导向），Repository 出自 DDD（聚合/领域语言），Spring Data/
> NestJS/Laravel 已让 repository 赢下命名战争但语义仍是 DAO 形状；本栈取 dao 作端口名（对照
> boot2 家族 mapper）、repository 作适配器名（行业零解释成本）。同文件判据（同层+同依赖闭包+
> 同变更节奏）决定了 service trait+impl 同文件，而 dao 端口与 repository 适配器分包——
> 中间隔着依赖方向（见 §1 依赖规则）。

- **每实体一份 `TableCodec[T]`**（无反射的代价，后续 gen 生成器产这份样板）：
  `name/cols/insert_cols/update_cols/from_row/id_of/del_col/order_col`；
  `get` 返回 `N` 的列不写/不覆盖（updateById 语义在 builder 层统一）；
  `del_col: Some("is_deleted")` = 逻辑删，BaseDao 自动追加 `del_col = 0` 过滤；
  **insert 跳过 N 值列**（null 不插入，列默认值生效，build_insert 实现）；
- **单表 CRUD 不写 SQL**——`BaseDao[T]` 模板全包（`insert/update_by_id/remove_by_ids/find_by_id/
  find_one/list/count/page`）；业务查询（join、专列）才手写 SQL（`user_page.mbt` 是样板）；
- 行映射 `row_user` 按列名取（`row_text/row_i64/row_opt_*`，手写行映射（无反射））；
  敏感列**照常进 `cols`**（读面需要：password/salt 登录密文校验/改密要读）；
  「不回显」的落点在 **dto 出参装配**——`user_json` 不装配该键即可（user_table.mbt 头注原话），
  把列剪出 cols 会让行映射恒 None 直接断业务；
- 连接缝在 `repository/dialect.mbt`：`Conn` trait（query/execute/begin/commit/rollback/close）+ 每库一个 Box 包装 + `open_conn` 按 `MLDONG_DB_DRIVER` 分发（现仅 mysql，新方言=新 Box+新分支）；q/x/close_conn/tx_* 全部泛型中性，行映射走 moondb.Row——**BaseDao/SQL builder 零方言**。事务写法见 §5。

### 3.5 service（业务唯一收口）

```moonbit
// 纯规则抽纯函数（零 IO 零 async，moon test 不连库直跑）
fn validate(req : @dto.UserSaveReq) -> String? { ... }

// ctx 第一参 = 框架请求上下文（core/ctx.mbt：user_id/login_id/app_code；goframe 同位）——
// 审计操作人与后续业务身份消费（数据权限等）的统一入口，controller 用 @web.ctx_of 装配；
// app_code 由 ctx_of 按请求头装配（缺省 platform，boot2 LoginUserHolder.getAppCode 同位——
// 菜单树/路由菜单/路由同步按域过滤都从这读）
pub(open) trait UserService { ... }
pub(all) struct UserServiceImpl[R] { dao : R }
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn save(self, ctx, req) { ... }
```

- 错误码语义：参数错 `InvalidInput`、不存在 `NotFound`、查重冲突 `Conflict`、业务失败 `Business`；
- **NOT NULL 列必须给业务默认值**（save 时 `admin_type: Some(2)`、`is_locked: Some(0)`）——
  分页过滤 `admin_type <> 1` 会因 NULL 三值逻辑漏行，落 NULL 是事故；
- **密码机制**（对齐 boot2）：save 不收用户自报密码，发默认密码 + 8 位随机盐
  （散列 `md5(明文+盐)` 小写 hex，见 `core/password.mbt`）；默认密码走**配置常量 Holder**
  （框架件 `core/config_holder.mbt`，module.mbt 装配闭包注入 service，boot2 ConstantContextHolder 同位：env 优先 → 常量表 →
  默认值回填；key `M_DEFAULT_PASSWORD` 缺省 `@core.DEFAULT_PASSWORD`="123456"，config
  写路即时刷新），service 经构造闭包注入不依赖 holder 类型；TableCodec 只把 password/salt
  放进 `insert_cols`；password/salt **也进读面 `cols`**（登录密文校验必须可读），
  不回显靠 dto 出参装配不带这两个键（detail 永不泄密文）；改密是独立端点的活；
- 查询组装：业务硬条件 + `w.append(req.m)`（m_ 动态条件）+ keywords 多列 OR（`w.raw`），
  参考 `UserServiceImpl::page`。

### 3.6 controller（薄端点）

```moonbit
// 权限码片段与端点同文件（对齐 boot2 权限注解位置）——详见 [permissions.md](permissions.md)
pub fn user_policy() -> @guard.RoutePolicy { ... }

pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.UserService, R : @svc.RbacService]
  register(ctx, svc, rbac, g, auth, dept_list) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  // register 本身带 raise；注册失败由 module.mbt 组合根统一 abort（不要 catch 透传，
  // fragile_catch_all warning 会破「warnings 基线 = 0」）
  g.post(ctx, "/sys/user/save", save_handler)
  ...
}
```

- `@web.wrap` 是统一异常处理的**唯一**落点（moonback handler 无 raise 通道，中间件是
  App 全局作用域先于路由匹配，都做不了这事）——handler 闭包只许抛 `MldongError`；
- 响应只准用 `@core.ok_empty/ok_data/ok_page`，形状对齐 boot2 `CommonResult/CommonPage`
  （`recordCount/totalPage/pageSize/pageNum/rows`）；
- 中间表类端点（grantRole）读 `userId/roleIds` 用 `@core.get_i64/get_i64_array`（雪花字符串兼容）。

## 4. sqlbuilder 与 m_ 通用查询（core）

```moonbit
let w = @core.where_()
let _ = w.eq("t.is_deleted", @core.I(0))       // SqlValue：S(串)/I(int)/L(int64)/N(null)
let _ = w.ne("t.admin_type", @core.I(1))
let _ = w.append(req.m)                         // m_ 动态条件并入
w.raw("(t.real_name like ? or t.user_name like ?)", params)   // 手写片段走 raw（参数化）
let (sql, params) = @core.build_select("sys_user", cols, w, orders=[("create_time", true)], limit=10, offset=0)
```

- `Wrapper` 条件法：`eq/ne/gt/ge/lt/le/like/not_like/like_pat/in_/not_in/raw/append`；
  `build()` 出 `(where_sql, params)`，`build_select/build_insert/build_update/build_delete` 出整句；
  **N 值在 insert/update 里跳过**（null 不覆盖语义）；
- `m_` 约定（mldong 框架同款）：入参键 `m_{OP}_{camelCol}`（3 段）或 `m_{alias}_{OP}_{col}`（4 段带表别名）；
  操作符 13 个 `EQ/NE/GT/GE/LT/LE/LIKE/NLIKE/LLIKE/RLIKE/BT/IN/NIN`（LLIKE=`%v`、RLIKE=`v%`，别反）；
  列名 camelCase 自动转 snake_case；空值跳过、非法操作符跳过、列名形状白名单（`is_field_safe`）防注入；
- keywords 关键字搜索：`keywords + searchKeys`（多列 OR like；searchKeys 可带表别名），
  service 侧用 `@core.parse_keywords_with_raw` 应用列白名单。

## 5. 事务

现状：**多写操作在 repository 原地开局部事务**（`perm_repository.mbt` 的 `grant_roles/grant_menus`
是样板）：`open_conn → begin → errdefer{rollback; close} → 语句 → commit → close`。
正式的事务模板在路线图上，但**参照对象不是 jeeflow-moon 的旧形状**：它原来把"环境连接"做成进程级全局
`Ref`，并发请求会互相提交、并把别人已确认的写入抹掉（真库实测复现过）。该缺陷在 jeeflow-moon 0.1.27 修掉，
现读参照＝修后的形状：**句柄随仓储实例走、请求边界新建派生实例**（见其
[`docs/CHANGELOG.md`](https://github.com/mldong/jeeflow-moon/blob/master/docs/CHANGELOG.md) 的 0.1.27 一节）。
本仓的对应载体是 `core.Ctx`（service 第一参已经是它 ⇒ 派生入口挂在 `Ctx` 上，不在仓储上再挂一层）——
**不要**照搬 contextvars/AsyncLocalStorage 那种类比，本栈没有 task-local。
就位后 grant 写路收敛过去——新写多语句事务先照 grant 样板，别发明第三种写法。

## 6. 模块化（sys/dev/biz）

- 模块 = moon.work 的一个 member（如 `modules/sys` = `mldong/moon-sys`）+ 六件套子包 +
  根包 `module.mbt` 自注册；
- `module.mbt`：dao/service 构造 + `register_*` 路由注册全收模块内，main 每模块一行
  `ctx.use_(@<mod>.install(config, g, auth, holder, enum_registry))`（**装配函数叫 `install`**——`module` 是保留字；
  holder/enum_registry 是框架级常量与枚举字典注册中心，main 建实例传入）；注册失败 `abort`（启动期错误响亮失败）；
- 权限码片段由模块聚合：`@sys.policy()` = `merge_policy(user_policy, role_policy)`，
  main 再并全局豁免面——详见 [permissions.md](permissions.md)；
- 新模块/新表操作手册：[adding-module.md](adding-module.md)。

## 7. 错误码与信封

- 信封：HTTP 恒 200 + `{"code":0,"msg":"ok","data":..}`；分页 data 形状 `recordCount/totalPage/pageSize/pageNum/rows`；
- 业务错误 `MldongError`（`core/error.mbt`）：`Internal 99990000` / `InvalidInput 99990001` /
  `NotFound 99990002` / `Conflict 99990003` / `Business 99990004` / `InvalidParam 99999999`
  （@Validated 参数校验档，UC-0610 在用）——raise 上抛，wrap 统一转信封；
- 鉴权错误走 moon-token：**HTTP 恒 200**，`99990403`（未登录/token 失效/无权限共用）由
  `core-web/guard.mbt` 的 `on_error` 产出；`99990401` 只归登录端点「用户名或密码错误」——
  详见 [permissions.md](permissions.md) §4.4。
