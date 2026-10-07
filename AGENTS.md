# mldong-moon · AGENTS.md

> AI 协作须知：mldong 快速开发框架 · MoonBit 栈（第 14 栈）

## 1. 项目定位

mldong-moon 是 mldong 快速开发框架的 **MoonBit 语言实现**，与 mldong 框架的接口契约保持**一致**：
同样的 URL、同样的 `{"code":0,"msg":"..","data":..}` 信封、同样的分页形状、同样的权限码
（`sys_menu.code`）与鉴权失败码（99990401/99990403）。

**本仓同时是后续代码生成器的模板骨架**——新增表/模块时严格照 `modules/sys` 的六件套写法
（见 [doc/adding-module.md](doc/adding-module.md)），写法漂移会让生成器模板失真。

公开开源仓（GitHub `mldong/mldong-moon`，Apache-2.0）。**任何密钥/密码不得入仓**：
数据库凭据只走 `MLDONG_DB_*` 环境变量，`core/mysql_config.mbt` 的默认值不含密码（红线）。

## 2. 仓库结构

```
mldong-moon/
├── moon.work            # workspace: ./core ./core-web ./modules/{sys,dev,app} ./cmd ./cmd/gen
├── AGENTS.md            # 本文件
├── README.md            # 面向人的总览（快速开始/文档导航/路线图；接口细节在 doc/api.md）
├── core/                # mldong/moon-core —— 框架无关底座，零 web/ORM 依赖
│   ├── error.mbt        #   MldongError（99990000~99990004 业务档 + 99990406 权限档 + 99999999 参数校验档）
│   ├── result.mbt       #   响应信封 ok_empty/ok_data/fail/ok_page
│   ├── sqlbuilder.mbt   #   Wrapper 条件 + build_select/insert/update/delete（中性 SQL 构建）
│   ├── query.mbt        #   m_ 通用动态查询（13 操作符 + keywords）与防注入白名单
│   ├── jsonx.mbt        #   Json 取值（get_i64/text_or/get_i64_array…）
│   ├── id_gen.mbt       #   雪花 ID（next_id）+ 时间
│   ├── config_holder.mbt#   配置常量 Holder（框架件：main 建实例传各模块，sys 灌入/刷新，dev/biz 只读）
│   ├── ctx.mbt         #   请求上下文 Ctx（审计操作人显式传参，禁全局 holder）
│   ├── password.mbt    #   md5(密码+盐) + 随机盐（登录密文校验）
│   ├── op.mbt          #   SqlValue 构造（S/I/L/D/B/N）
│   ├── enum_dict.mbt    #   枚举字典注册中心（框架件：IntVal/int_dict + DictModel/Registry，各模块装配期灌自己的声明；sys 样板 modules/sys/enums/ 逐枚举一文件）
│   └── mysql_config.mbt #   MysqlConfig::from_env（MLDONG_DB_*）
├── core-web/            # mldong/moon-core-web —— moonback 适配层（全工程 web 依赖唯一收口）
│   ├── common.mbt       #   wrap（统一错误转信封）+ json_body
│   └── guard.mbt        #   merge_policy / on_error（鉴权失败恒 200+99990403 信封）/ token_of（剥 Bearer）
├── modules/sys/         # mldong/moon-sys —— 业务模块样板（六件套）
│   ├── entity/ dto/ dao/ repository/ service/ controller/
│   ├── enums/           #   18 个业务枚举逐文件（常量 + all()；registry.mbt 装配期灌注册中心）
│   └── module.mbt       #   模块自注册 + policy() 聚合 + rbac_provider()
├── modules/dev/         # mldong/moon-dev —— dev_schema 台账三件套（boot2 dev 22 端点）+ 库元数据底座（doc/gen-metadata.md）
│   ├── entity/ dto/ dao/ repository/ service/ controller/ + enums/（4 个 dev 枚举）
│   └── metadata/ + metadata-mysql/  #   MetadataDao 端口 + information_schema 实现（gen/importTable 一件两用）
├── modules/app/         # mldong/moon-app —— APP 检查升级（免登录 UC-0610；校验失败 99999999 = core InvalidParam 新档；薄模块仅 controller）
├── cmd/main/            # 装配入口：鉴权 + 模块挂载 + listen :18680
├── cmd/gen/             # 代码生成器（读 MetadataDao 产六件套，gen-out/ 不入仓）
├── e2e/                 # 黑盒回归矩阵（run.sh 总入口，十六套 370 用例，真库）
└── doc/                 # 深入文档（AI 上手按序读）
    ├── layering.md      #   分层规范（六件套、依赖规则、BaseDao、sqlbuilder、m_）
    ├── permissions.md   #   权限鉴权（moon-token 集成、RBAC 链、appCode）
    ├── api.md           #   接口文档（全部端点 + 权限码 + 行为语义，按需查）
    ├── adding-module.md #   新增模块/新表操作手册（gen 首选路 + 六件套清单 + 自检清单）
    ├── gen-metadata.md  #   gen 生成器/元数据底座（碰 gen/dev_schema 时读）
    ├── base-contract.md #   家族契约 runner 跑法 + 端点比对结论
    └── sql/             #   mysql-schema-all.sql（建库+全表+种子，一条命令初始化）
```

## 3. 工具链与本地运行

MoonBit 工具链（moon 0.1.x + moonc v0.10.x），workspace 多模块，目标档位 **wasm**（moonrun 执行；
native 档由 CI 承担）。所有命令在仓根执行：

```bash
moon check                     # 类型检查（0 errors 为绿；warnings 已知类别见 §5）
moon run --target wasm cmd/main  # 起服务，默认 127.0.0.1:18680
```

启动前设库凭据（**默认值不含密码，密码必须走 env**）：

```bash
export MLDONG_DB_HOST=127.0.0.1 MLDONG_DB_PORT=3306
export MLDONG_DB_USER=root MLDONG_DB_PWD=<密码> MLDONG_DB_NAME=mldong-moon
```

首次建库：`mysql -u root -p --default-character-set=utf8mb4 < doc/sql/mysql-schema-all.sql`
（一条命令：建库 + 全表 + 种子；utf8mb4 防中文注释乱码——会被 gen 读进生成物）。

回归（服务起后，真库黑盒矩阵，十六套 370 用例）：

```bash
BASE=http://127.0.0.1:18680 bash e2e/run.sh   # 汇总 "总计: OK n FAIL 0" 为绿
```

用例即脚本（e2e/*.py，标准库零依赖）；动了鉴权/RBAC 必须全量跑，普通改动跑相关套件。

单端点冒烟（快速探活）：

```bash
curl -s -X POST http://127.0.0.1:18680/sys/login \
  -H 'Content-Type: application/json' -d '{"userName":"superAdmin","password":"123456"}'
# 用返回的 token 打受保护端点：
curl -s -X POST http://127.0.0.1:18680/sys/user/page \
  -H "Authorization: Bearer <token>" -H 'Content-Type: application/json' \
  -d '{"pageNum":1,"pageSize":10}'
```

## 4. 上手路线（新会话按此顺序）

1. [README.md](README.md) —— 总览与快速开始；
2. [doc/layering.md](doc/layering.md) —— 分层规范（改代码前必读）；
3. [doc/permissions.md](doc/permissions.md) —— 权限/鉴权（碰登录、权限码、appCode 前必读）；
4. [doc/adding-module.md](doc/adding-module.md) —— 加表/加模块时照抄；
5. [doc/gen-metadata.md](doc/gen-metadata.md) —— 碰 gen/dev_schema/元数据时读；
6. [doc/base-contract.md](doc/base-contract.md) —— 家族契约 runner 跑法 + 已存在端点比对结论 + 未存在接口按模块清单（补模块前先看）；
7. [doc/api.md](doc/api.md) —— 端点行为按需查（不用通读）；
8. 模板样板真身在 `modules/sys`（user 全链 + role + RBAC 中间表），文档与源码冲突时**以源码为准**并回来修文档。

## 5. 关键认知 / 坑（先读再动手）

- **moonback handler 没有 raise 通道**（`Handler = async (Request, Responder) -> Unit`），
  统一异常处理落 `@web.wrap`：业务闭包只许抛 `MldongError`，wrap 负责转 9999xxxx 信封。
  **中间件做不了这事**（moonback 中间件是 App 全局作用域且先于路由匹配执行）。
- **信封 HTTP 恒 200**（含鉴权失败）：业务码进 body（99990403=token 失效、99990406=无权限码、99999999=参数校验失败与唯一键冲突、99990401 只归登录
  「用户名或密码错误」）——boot2 GlobalExceptionHandler / goframe WriteJson 同约定，vben5 按 code
  分支不吃 HTTP 状态；新端点别再直出 4xx（契约 runner UC-0101/0113 都按此断，详见 doc/base-contract.md §3）。
- **moon_zod 是 strip 模式**：schema 里没声明的字段会被**丢弃**。id/deptId 这类"不校验但要存活"
  的字段必须写 `"id": @moon_zod.any().optional()` 占位。
- **雪花 ID 全链字符串化**：JS Number 53 位精度装不下 64 位雪花，入参出参一律 String
  （`jsnow`/`id.to_string()`），同款坑统一修。
- **NULL 三值逻辑**：`admin_type <> 1` 会漏掉 NULL 行——save 必须给 NOT NULL 列默认值
  （admin_type=2、role_type=1），查询超管不可见过滤靠它。
- **moon_zod 的 like 语义**：LLIKE=`%v`（后缀）、RLIKE=`v%`（前缀），写测试断言别搞反。
- **MySQL `--` 注释后必须跟空格**；sys_role 建表语句是单空格排版，写 SQL 对比扫描器时注意 `\s+`。
- **TokenAuth 必须在 main 内构造**（不能顶层 `let`）：wasm 档顶层 let 在 `__moonbit_init` 阶段
  求值，那时平台熵未就绪，`opaque_style()` 当场 abort（cmd/main/main.mbt 头注同款警告）。
- **豁免面端点手取 token 必须用 `@web.token_of`**（剥 `Bearer ` 前缀 + cookie 兜底），
  否则拿到带前缀的串查不到会话，logout 幂等不报错、静默失效（已踩）。
- **模块包别名速查**（moon.pkg）：`@core`=moon-core、`@web`=moon-core-web、
  `@mb`=moonback、`@mbguard`=moon-token-moonback/guard、`@app`=moon-token/app、
  `@guard`=moon-token/guard、`@port`=moon-token-store/port、`@style`=moon-token/style、
  `@mem`=moon-token-store/memory；模块内 `@entity/@dto/@dao/@repo/@svc/@ctrl` 指 moon-sys 子包。
- **审计四件套**（create_time/create_user/update_time/update_user）：时间由 service/codec
  填；**操作人走框架 Ctx**——`core/ctx.mbt`（goframe ctx 显式第一参同位）：controller
  `@web.ctx_of(request)` 从登录主体装配 → **service 全方法第一参 `ctx : @core.Ctx`** →
  实体 create_user/update_user 取 `ctx.user_id` → TableCodec 写路面（insert 双列/update
  update_user，N 值跳过）。**不要做全局 holder**：moonbitlang/async 无 task-local，协同式
  async 请求交错会串号（boot2 ThreadLocal 无安全对应物；goframe 的 ctx 同样是显式传参，
  不是隐式全局）。后续业务身份消费（数据权限/appCode 过滤/trace）一律扩 Ctx 字段；
  gen 模板已内置，手写表照 user_service 形状。
- **warnings 基线 = 0**（`moon check` 0 errors 0 warnings，10-05 全量清零）：改动后出现任何
  新告警就地修掉，常见修法——
  * `fragile_catch_all`：路由注册的 `catch { e => raise e }` 透传**直接删**（register 本身带
    raise，module.mbt 组合根统一 abort）；错误转换处绑 `e` 并转 `MldongError`；
  * `implicit_impl_as_method`：trait impl 的方法被具体类型直调时补 `pub extend Type with Trait::{..}`
    （每个 repository/service 文件的 extend 必须**全量**列出 impl 方法，漏一个就还告警）；
  * `deprecated`：`substring(start=e)` → `s[e:].to_owned()`、`substring(start=0,end=i)` →
    `s[:i].to_owned()`、StringView `.to_string()` → `.to_owned()`、大写化 `Char::from_int(i-32)` →
    `(i-32).unsafe_to_char()`（ASCII 区间安全）；
  * `reserved_keyword`：`alias`/`module` 是保留字（query.mbt 用 `tbl`，模块装配函数叫 `install`）；
  * `async` 无 await 点会报 `unused_async`：纯同步闭包直接写 `fn(request)`（sync 可用在 async 位）；
  * 包根 moon.pkg 声明 `supported_targets`（否则向上游包传播提示）。

## 6. 协作约定

- **commit 前**：`moon check` 0 errors + `bash e2e/run.sh` 全绿（或至少相关套件）；
  动了鉴权/RBAC 必须全量跑。
- **git**：明确路径 `git add <文件>`，禁止 `git add -A`/`git add .`；
  不绕过 hook（无 `--no-verify`）。
- **接口契约**：URL、信封、错误码、分页形状、权限码以 mldong 接口契约为准，不私造形状；
  字段名一律 camelCase（JSON）/ snake_case（DB 列）。
- **文档同步**：改分层/权限行为时同步改 doc/ 对应篇，README 路线图勾状态。
