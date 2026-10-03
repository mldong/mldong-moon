# 分层规范

> mldong-moon 的分层是 13 栈同构的：业务收 service、dao 解耦 ORM、controller 只做校验与转发。
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
dao-mysql（手写 SQL + 行映射；BaseDao[T] 模板 + TableCodec；moondb+moonmysql 全工程唯一入口）

entity（纯数据 struct，零行为）      dto（入参 schema + parse_* + Req + 出参装配）
core（错误码/信封/sqlbuilder/m_ 查询/雪花/时钟——零 web）   core-web（moonback 适配——wrap/守卫工具）
```

**依赖规则（硬约束）**：

| 规则 | 理由 |
|---|---|
| `core` 不 import 任何 web/ORM 包 | 框架无关底座，模块间共享、可独立测试 |
| web 依赖（moonback）只出现在 `core-web` 与各模块 `controller` | 换 web 框架只动这两处 |
| ORM 依赖（moondb/moonmysql）只出现在各模块 `dao-mysql` | 换库/换驱动只动这一处 |
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
| dao-mysql | `dao-mysql/user_table.mbt`（TableCodec+row 映射）、`user_mysql.mbt`（trait impl）、`user_page.mbt`（join 版查询） | SQL 与行映射 | 业务规则 |
| service | `service/user_service.mbt` | `trait UserService` + `UserServiceImpl[R]`：校验、查重、默认值、错误码 | web/ORM 类型 |
| controller | `controller/user_controller.mbt` | `policy()` 权限码片段（与端点同文件）+ `register()` 薄端点 | 业务逻辑 |

## 3. 各层写法要点

### 3.1 entity

- 纯 `struct`，字段与表列一一对应（snake_case 命名字段）；可空列用 `Option`；
- 雪花主键 `Int64`，**进出 JSON 一律字符串**（JS 53 位精度，13 栈同坑同修）；
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

### 3.4 dao-mysql（实现）

- **每实体一份 `TableCodec[T]`**（无反射的代价，后续 gen 生成器产这份样板）：
  `name/cols/insert_cols/update_cols/from_row/id_of/del_col/order_col`；
  `get` 返回 `N` 的列不写/不覆盖（MyBatis-Plus updateById 语义在 builder 层统一）；
  `del_col: Some("is_deleted")` = 逻辑删，BaseDao 自动追加 `del_col = 0` 过滤；
- **单表 CRUD 不写 SQL**——`BaseDao[T]` 模板全包（`insert/update_by_id/remove_by_ids/find_by_id/
  find_one/list/count/page`）；业务查询（join、专列）才手写 SQL（`user_page.mbt` 是样板）；
- 行映射 `row_user` 按列名取（`row_text/row_i64/row_opt_*`，MyBatis resultMap 的手写对应物）；
  不回显的列（password/salt/avatar）不进 `cols`；
- 连接助手在 `dao-mysql/conn.mbt`（`open_conn/q/x/row_*/to_db_values`），事务写法见 §5。

### 3.5 service（业务唯一收口）

```moonbit
// 纯规则抽纯函数（零 IO 零 async，moon test 不连库直跑）
fn validate(req : @dto.UserSaveReq) -> String? { ... }

pub(open) trait UserService { ... }
pub(all) struct UserServiceImpl[R] { dao : R }
pub impl[R : @dao.UserDao] UserService for UserServiceImpl[R] with fn save(self, req) { ... }
```

- 错误码语义：参数错 `InvalidInput`、不存在 `NotFound`、查重冲突 `Conflict`、业务失败 `Business`；
- **NOT NULL 列必须给业务默认值**（save 时 `admin_type: Some(2)`、`is_locked: Some(0)`）——
  分页过滤 `admin_type <> 1` 会因 NULL 三值逻辑漏行，落 NULL 是事故；
- **密码机制**（对齐 boot2）：save 不收用户自报密码，发默认密码 + 8 位随机盐
  （`@core.DEFAULT_PASSWORD` + `random_salt`，散列 `md5(明文+盐)` 小写 hex，见
  `core/password.mbt`）；TableCodec 只把 password/salt 放进 `insert_cols`，读面 `cols` 不带
  （detail 不回显密文）；改密是独立端点的活（resetPwd 类，13 栈各自有）；
- 查询组装：业务硬条件 + `w.append(req.m)`（m_ 动态条件）+ keywords 多列 OR（`w.raw`），
  参考 `UserServiceImpl::page`。

### 3.6 controller（薄端点）

```moonbit
// 权限码片段与端点同文件（对齐 boot2 @SaCheckPermission 注解位置）——详见 [permissions.md](permissions.md)
pub fn user_policy() -> @guard.RoutePolicy { ... }

pub fn[S, P, T : @svc.UserService, R : @svc.RbacService] register(ctx, svc, rbac, g) -> Unit raise {
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let id = svc.save(@dto.parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  g.post(ctx, "/sys/user/save", save_handler) catch { e => raise e }
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
- `m_` 约定（13 栈同款）：入参键 `m_{OP}_{camelCol}`（3 段）或 `m_{alias}_{OP}_{col}`（4 段带表别名）；
  操作符 13 个 `EQ/NE/GT/GE/LT/LE/LIKE/NLIKE/LLIKE/RLIKE/BT/IN/NIN`（LLIKE=`%v`、RLIKE=`v%`，别反）；
  列名 camelCase 自动转 snake_case；空值跳过、非法操作符跳过、列名形状白名单（`is_field_safe`）防注入；
- keywords 关键字搜索：`keywords + searchKeys`（多列 OR like；searchKeys 可带表别名），
  service 侧用 `@core.parse_keywords_with_raw` 应用列白名单。

## 5. 事务

现状：**多写操作在 dao-mysql 原地开局部事务**（`perm_mysql.mbt` 的 `grant_roles/grant_menus`
是样板）：`open_conn → begin → errdefer{rollback; close} → 语句 → commit → close`。
正式的事务模板（环境连接 + 嵌套复用，参照 jeeflow-moon `MysqlTxTemplate`）在路线图上，
就位后 grant 写路收敛过去——新写多语句事务先照 grant 样板，别发明第三种写法。

## 6. 模块化（sys/dev/biz）

- 模块 = moon.work 的一个 member（如 `modules/sys` = `mldong/moon-sys`）+ 六件套子包 +
  根包 `module.mbt` 自注册；
- `module.mbt`：dao/service 构造 + `register_*` 路由注册全收模块内，main 每模块一行
  `ctx.use_(@<mod>.module(config, g, auth))`；注册失败 `abort`（启动期错误响亮失败）；
- 权限码片段由模块聚合：`@sys.policy()` = `merge_policy(user_policy, role_policy)`，
  main 再并全局豁免面——详见 [permissions.md](permissions.md)；
- 新模块/新表操作手册：[adding-module.md](adding-module.md)。

## 7. 错误码与信封

- 信封：HTTP 恒 200 + `{"code":0,"msg":"ok","data":..}`；分页 data 形状 `recordCount/totalPage/pageSize/pageNum/rows`；
- 业务错误 `MldongError`（`core/error.mbt`）：`Internal 99990000` / `InvalidInput 99990001` /
  `NotFound 99990002` / `Conflict 99990003` / `Business 99990004`——raise 上抛，wrap 统一转信封；
- 鉴权错误走 moon-token：`99990401`（未登录，HTTP 401）/ `99990403`（无权限，HTTP 403），
  由 `core-web/guard.mbt` 的 `on_error` 产出——见 [permissions.md](permissions.md)。
