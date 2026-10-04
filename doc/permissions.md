# 权限与鉴权（moon-token 集成）

> 鉴权底座 = [mldong/moon-token](https://github.com/mldong/moon-token)（owner 自研，Sa-Token 机制
> 的 MoonBit 重写）。本文讲三件事：登录态怎么签发流转、权限码从哪来到哪去、appCode 多应用怎么隔离。
> 改鉴权/RBAC 相关代码前必读；改完按 §7 矩阵复跑。

## 1. 集成面总览

| moon-token 侧 | 本仓接点 |
|---|---|
| `app.TokenAuth`（登录/注销/鉴权/rotate 引擎） | `cmd/main` 构造，泛型 `[TokenStore, PermissionProvider]` |
| `store/memory.MemoryStore`（当前会话存储） | `cmd/main` 注入；文件/Redis 后端等第三方驱动稳定后切换 |
| `store/port.PermissionProvider`（供数端口：码/角色/超管三问） | `modules/sys/service/rbac_service.mbt` 的 `RbacServiceImpl` 真实现（查库） |
| `guard.RoutePolicy` + `Guard`（逐路由守卫） | 各 controller `policy()` 片段 → 模块聚合 → main 合并 |
| `moon-token-moonback/guard`（moonback 适配） | `core-web` 的 `on_error`（失败信封）；controller 的 `g.post` 注册 |
| `style.opaque_style()`（不透明 token） | `cmd/main` 构造项；**必须在 main 内构造**（wasm 顶层 let 无熵会 abort） |

## 2. 登录 / 注销（`controller/login_controller.mbt`）

- 端点 `POST /sys/login`、`POST /sys/logout`，走**全局豁免面**（main 里 `.exempt(...)`，guard 不拦）；
- 密文校验对齐 boot2：**`md5(密码明文 + 盐)` 小写 hex**（注意顺序：密码在前盐在后；
  `core/password.mbt` 用 mooncrypt md5 + UTF-8，单测对标准向量）；校验顺序 = 存在 →
  锁定（`is_locked=1` 拒绝）→ 密文；用户不存在与密码错**同话术同码**（401 + 99990401
  “用户名或密码错误”，防枚举，boot2 两支同抛 USER_NOT_EXIST 同设计；mldong 框架登录失败码各自
  为政——boot2=10000001、其余各语言实现自定，本栈定案 401+99990401 走鉴权失败语义）；
- `login_id = sys_user.id 字符串`（对齐 sa-token `StpUtil.login(user.getId())`），
  **纯 id，不含任何后缀**——appCode 等会话属性走 extra（§5），别复合进 login_id
  （会污染按 login_id 的搜索面，owner 定过案）；
- 响应 data：`token / refreshToken / userId`（契约字段名对齐 mldong 框架约定 LoginVO，userId = login_id = sys_user.id 字符串）；
- **注销手取 token 必须用 `@web.token_of`**（剥 `Bearer ` 前缀 + Authorization cookie 兜底）——
  直接拿 `Authorization` 头会带前缀查不到会话，logout 幂等不报错、**静默失效**（已踩）。

## 3. main 装配（`cmd/main/main.mbt`）

```moonbit
let token_cfg = @app.TokenConfig::default()
token_cfg.token_prefix = "Bearer"                       // 对齐 mldong 框架约定（sa-token token-prefix + vben5）
let auth = @app.TokenAuth::new("user", token_cfg,
  @mem.MemoryStore::new("user"),
  @sys.rbac_provider(config),                            // 供数方 = RBAC 真实现
  @style.opaque_style())
// 总策略 = 全局豁免面 + 各模块片段聚合
let policy = @web.merge_policy(
  @guard.RoutePolicy::new().exempt("/sys/login").exempt("/sys/logout"),
  @sys.policy())
let g = @mbguard.Guard::new(auth, policy).with_on_error(@web.on_error)
```

要点：
- `token_prefix="Bearer"` 与 `@web.token_of` 是同一约定，两头别只改一头；
- `with_on_error(@web.on_error)` 把 moon-token 默认的空体失败响应替换成 mldong 信封（§6）；
- 受保护端点在 controller 里用 `g.post(ctx, path, handler)` 注册（守卫版注册），
  豁免面端点用 `ctx.post`。

## 4. 权限码：声明、收集、判定

### 4.1 声明位置——与端点同文件（对齐 boot2 `@SaCheckPermission` 注解位置）

每个实体 controller 导出 `policy()` 片段，全部**显式 rule**：

```moonbit
pub fn user_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/user/save", ["sys:user:save"]))
    .rule(@guard.RouteRule::make("/sys/user/page", ["sys:user:page"]))
    ...
}
```

### 4.2 收集链路

实体片段（controller 同文件）→ 模块聚合（`module.mbt` 的 `@sys.policy()` =
`merge_policy(user_policy, role_policy)`）→ main 并进总 policy 交 `Guard`。
新实体 = 在它的 controller 里加片段 + 模块聚合处并一行。

### 4.3 判定顺序与"不一致场景"

moon-token 判定：**豁免 > 例外清单（显式 rule）> 推导（derive_perm，URL 段冒号连）> 只验登录**。

- 推导只是兜底，**本仓全部显式声明**，不依赖推导；
- URL 与权限码不一致的场景（boot2 实锤：`/sys/user/locked` 与 `/sys/user/unLocked` 共用双码 OR）
  一律在片段里写显式 rule + 多码（默认 OR 语义）表达；
- 新端点必须在同文件补 rule，漏了 = 只验登录态（有 token 就能打），是安全事故不是小事。

### 4.4 失败响应

`core-web/guard.mbt` 的 `on_error`：HTTP 401/403 + mldong 信封
`{"code":99990401,"msg":<TokenError 原因>,"data":null}`（99990401 未登录 / 99990403 无权限 /
400→99990001 / 其余→99990000）。对齐 mldong 接口契约，前端按 code 区分跳登录还是报无权限。

## 5. appCode 多应用机制

对齐 boot2：登录头 `appCode`（缺省 `platform`）→ 会话级定死 → role/menu 按 `app_code` 双过滤。
**落法 = moon-token 0.1.9 `extra` 会话属性通道**（首版曾复合进 login_id，owner 否了，见 §2）：

- 登录端点塞 extra 三键：`appCode`（登录头）、`ip`（客户端 IP）、`ua`（原样 User-Agent；
  boot2 `loginBrowser` 存的就是原样 UA，"os" 是日志层解析的，骨架同口径存原样）；
- 供数方 `RbacServiceImpl` 三方法从 `extra` 里读 appCode 传给 DAO（缺省 platform），
  SQL 里 `role.app_code`/`menu.app_code` 双过滤；
- 超管判定（`admin_type=1`）只看用户属性，**与 appCode 无关**（boot2 同）；
- 会话语义：moon-token 默认 `Coexist` + max_sessions=12——**同用户不同 appCode 的会话共存**
  （各自独立 token，互不顶），与 boot2 sa-token is-concurrent 同语义；
- extra 随 rotate 存活（moon-token 单测覆盖）；新增会话级属性照三键模式塞 extra，别走 login_id。

## 6. RBAC 真码链

**权限码的真实来源 = `sys_menu.code`**（boot2 RbacService 同源），链路：

```
sys_user_role ──▶ sys_role (app_code 过滤) ──▶ sys_role_menu ──▶ sys_menu (type=按钮, app_code 过滤) ──▶ code 去重
```

组织定稿（mldong 框架同构）：

- **中间表 `sys_user_role`/`sys_role_menu` 不立六件套**——boot2 只有 MP 实体无独立
  controller/service；授权挂主表端点（`POST /sys/user/grantRole`，`{userId, roleIds}`），
  **全量替换**式写入（删旧插新，`repository/perm_repository.mbt` 局部事务样板）；
  `sys_role_menu` 写路 dao 层备好、暂无暴露端点（对齐 mldong 框架约定）；
- 查询归 `RbacDao` 端口（`dao/perm_dao.mbt`）：`find_user_auth_by_name/by_id`（登录身份）、
  `find_role_codes`、`find_perms_by_user`（码链 join）、`grant_roles/grant_menus`（写路）；
- `RbacServiceImpl` **双 impl**：`RbacService`（授权业务，登录端点/user 控制器用）+
  `PermissionProvider`（moon-token 供数，main 装配用）；DAO 的 `MldongError` 在端口边界转
  `TokenError::Store`（供数方故障语义）；
- login 响应里 `userId` 就是纯用户 id（= login_id）；guard 鉴权时按 token 找会话 → 用 login_id + extra
  问供数方要码集（带授权快照缓存，TTL 跟会话窗口同寿）。

## 7. 验收矩阵（改鉴权/RBAC 后必复跑）

种子：`superAdmin`（admin_type=1 超管）、`admin`（manage@platform）；临时数据用 SQL 造、跑完清。

**appCode（8 例）**：

| # | 用例 | 预期 |
|---|---|---|
| A1 | 登录带 `appCode: app1` | `userId` = 纯用户 id（无 `@app1` 后缀） |
| A2 | app1 会话打已授权端点 | 200（app1 码链生效） |
| A3 | 不带 appCode 头登录 | = platform；无权限端点 403 |
| A4 | 超管 + 任意 appCode | 200（超管跨 app） |
| A5 | 同用户先后登 app1/app2 | 两个 token 共存（app1 会话不被顶，app2 滤空 403） |
| A6 | 空 appCode 头 | = platform |
| A7 | 头名大小写混写（`appcode:`） | 生效（HTTP 头名不区分大小写） |
| A8 | 注销后旧 token | 401 |

**RBAC 真码（4 例）**：

| # | 用例 | 预期 |
|---|---|---|
| R1 | 无 sys:user:page 的用户打 page | 403（99990403） |
| R2 | SQL 授码后重登打 page | 200（码链生效） |
| R3 | 同会话打未授权端点（sys:role:page） | 403（精确单码，不多授） |
| R4 | 撤码后重登 | 403（撤销生效） |

**回归（4 例）**：login 200 且字段齐（token/refreshToken/userId）→ save/update/detail/grantRole/remove
全 0 → 负向（非法 JSON/缺字段）99990001 → 未带 token 打受保护端点 401。

**密码（10 例）**：正向 admin/123456 → 错密与不存在同话术同码（防枚举）→ 缺 password 字段 →
锁定用户拒登（“用户已锁定”）→ save 新用户默认密码可登 → detail 不回显 password/salt → rotate 回归。

**refreshToken（8 例，UC-0113）**：RR0 login 形状恰为 {token,refreshToken,userId} → RR1 rotate 出全新对 →
RR2 新 access 打受保护端点 200 → RR3 旧 refresh 重放 99990410 → RR4 旧 access 99990401 →
RR5 垃圾串 99990410 → RR6 rotate 延续 extra（platform 滤空仍 403、超管轮转后仍 200）→
RR7 登出后其 refresh 联动失效 99990410（moon-token logout 单一漏斗内建）。

## 8. 已知 TODO

- 会话存储切换文件/Redis 后端（moon-token 端口已预留，等第三方驱动库稳定）。
