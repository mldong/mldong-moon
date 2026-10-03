# mldong-moon

mldong 快速开发框架的 **MoonBit 栈**实现（第 14 栈）。目标是与既有 13 栈（boot2/3/4、fastapi、flask、django、nestjs、laravel、goframe、gin、hertz、salvo、csharp）保持接口契约一致：同样的 URL、同样的 `{"code":0,"msg":"..","data":..}` 信封、同样的分页形状、同样的权限码与鉴权失败码。

当前已落：`sys_user` 全链 CRUD + `sys_role` CRUD + 登录/注销 + moon-token 鉴权（RBAC 真码链 + appCode 多应用）。同时是后续模块与代码生成器的**模板骨架**。

## 技术栈

| 件 | 选型 | 说明 |
|---|---|---|
| Web 框架 | [moonbitlang/moonback](https://github.com/moonbitlang/moonback) 0.8.6 | MoonBit 官方 Web 框架 |
| 权限认证 | [mldong/moon-token](https://github.com/mldong/moon-token) 0.1.9 | 登录态/会话/RBAC 标准件（逐路由守卫 + 供数端口 + extra 会话属性） |
| 表单校验 | [Betterlol/moon_zod](https://github.com/Betterlol/moon_zod) 0.8.2 | 规则式校验，schema 收口在 dto 层 |
| DB 访问 | moonbitstack/moondb 0.2.0 + moonbitstack/moonmysql 0.7.3 | 手写 SQL（MyBatis 式 mapper），moondb 接口缝 + moonmysql 驱动 |
| 运行档位 | wasm（moonrun） | native 档可在 CI（Linux）构建 |

## 分层

```
controller（moonback handler + guard + 转发）
     │ 调
     ▼
service（业务逻辑唯一收口；纯规则抽纯函数）
     │ 调
     ▼
dao（端口 trait，签名只用 entity/dto/@core.Wrapper）
     │ 实现
     ▼
dao-mysql（手写 SQL + 行映射，moondb+moonmysql 全工程唯一入口）

entity（纯数据 struct） / dto（入参 schema + parse + Req + 出参装配）
core（零 web：错误码/信封/sqlbuilder/m_ 查询/雪花）
core-web（moonback 适配：wrap 统一错误转信封 / 守卫工具——全工程 web 依赖唯一收口）
```

模块按 `sys`（系统管理）/ `dev`（开发工具）/ `biz`（业务）划分，模块内六件固定：`entity / dto / dao / dao-mysql / service / controller`。

## 模块布局

```
mldong-moon/
├── moon.work                  # members: core / core-web / modules/sys / cmd
├── core/                      # mldong/moon-core：错误码、响应信封、分页、Json 取值、时钟、雪花 ID
├── core-web/                  # mldong/moon-core-web：wrap/json_body、guard 工具（policy 合并/失败信封/token_of）
├── modules/sys/               # mldong/moon-sys
│   ├── entity/                #   sys_user → User（类名去表前缀）
│   ├── dto/                   #   user_dto.mbt：moon_zod schema + parse_* + 出参装配
│   ├── dao/                   #   UserDao 端口 trait（user/role/rbac）
│   ├── dao-mysql/             #   BaseDao[T] 单表模板 + TableCodec + 手写 join SQL
│   ├── service/               #   UserService trait + Impl[R]；rbac_service.mbt = RBAC + moon-token 供数方
│   ├── controller/            #   端点注册 + policy() 权限码片段（与端点同文件）
│   └── module.mbt             #   模块自注册（main 每模块一行）
├── cmd/main/                  # 装配：鉴权（moon-token）+ 模块挂载 + listen :18680
└── doc/                       # 深入文档
    ├── layering.md            #   分层规范（六件套、依赖规则、BaseDao、sqlbuilder、m_）
    ├── permissions.md         #   权限鉴权（登录/守卫/RBAC 链/appCode + 验收矩阵）
    ├── adding-module.md       #   新增模块/新表操作手册
    └── sql/mysql-schema-all.sql  # 建库 + 全表 + 种子数据（一条命令）
```

## 接口（对齐 mldong 13 栈）

全部 `POST`，请求/响应 `application/json`，HTTP 恒 200，`code=0` 成功；鉴权端点带 `Authorization: Bearer <token>`。

| 端点 | 权限码 | 说明 |
|---|---|---|
| `/sys/login` | 豁免 | `{userName, password}` → `{token, refreshToken, userId}`；密文校验 `md5(密码+盐)` 对齐 boot2（错密与不存在同话术防枚举，失败 401+99990401）；会话 extra 带入 appCode/ip/ua |
| `/sys/refreshToken` | 豁免 | `{refreshToken}` → 全新 `{token, refreshToken, userId}`（全量轮转：旧 access+旧 refresh 同时失效；失败统一 `99990410` 不泄露原因） |
| `/sys/logout` | 豁免 | 注销当前 token |
| `/sys/user/save` | `sys:user:save` | 新增（用户名查重；不收密码，发默认密码 `123456` + 8 位随机盐，boot2 同机制；雪花 ID 全部字符串出入，防 JS 精度丢失） |
| `/sys/user/update` | `sys:user:update` | 修改（未传字段不覆盖，MyBatis-Plus updateById 语义） |
| `/sys/user/remove` | `sys:user:remove` | 逻辑删除 `{ids:[..]}` |
| `/sys/user/detail` | `sys:user:detail` | 单个 `{id}` |
| `/sys/user/page` | `sys:user:page` | 分页：join dept/post 名称 + m_ 动态条件 + keywords |
| `/sys/user/grantRole` | `sys:user:grantRole` | `{userId, roleIds}` 用户授权角色（全量替换） |
| `/sys/role/{save,remove,update,detail,page}` | `sys:role:*` | 角色 CRUD |

- 未登录 `HTTP 401 + {"code":99990401}`；无权限 `HTTP 403 + {"code":99990403}`；
- 分页请求 `{pageNum, pageSize, keywords?, searchKeys?, m_{OP}_{col}?...}`，响应 data 形状
  `recordCount/totalPage/pageSize/pageNum/rows`；
- `m_` 通用查询 13 操作符（EQ/NE/GT/GE/LT/LE/LIKE/NLIKE/LLIKE/RLIKE/BT/IN/NIN），
  3 段式 `m_EQ_userName` / 4 段式（带表别名）`m_t_LIKE_userName`；列名 camelCase 自动转
  snake_case，空值跳过、非法操作符跳过、列名形状白名单防注入；
- 错误码（骨架子集，码表对齐 13 栈）：`99990000` 内部 / `99990001` 参数校验失败 /
  `99990002` 数据不存在 / `99990003` 业务冲突 / `99990004` 业务失败；
- `appCode`：登录头（缺省 `platform`）定会话应用上下文，role/menu 按 `app_code` 双过滤，
  同用户不同 app 会话共存。

## 快速启动

前置：[MoonBit 工具链](https://docs.moonbitlang.com)（moon + moonrun），MySQL 5.7+/8.0。

初始化数据库（一条命令，内置建库 + 全表 + 种子数据）：

```bash
mysql -u root -p < doc/sql/mysql-schema-all.sql
```

启动（密码只走环境变量，默认值不含密码）：

```bash
export MLDONG_DB_HOST=127.0.0.1 MLDONG_DB_PORT=3306
export MLDONG_DB_USER=root   MLDONG_DB_PWD=<你的密码>   MLDONG_DB_NAME=mldong-moon

moon run --target wasm cmd/main     # 默认 127.0.0.1:18680

# 登录拿 token
curl -s -X POST http://127.0.0.1:18680/sys/login \
  -H "Content-Type: application/json" -d '{"userName":"superAdmin"}'
# 打受保护端点
curl -s -X POST http://127.0.0.1:18680/sys/user/page \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"pageNum":1,"pageSize":10}'
```

种子账号：`superAdmin`（超管，跨全部权限码）/ `admin`（manage@platform 角色）。

## 文档

| 文档 | 内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | AI 协作入口：结构、工具链、关键坑、上手路线 |
| [doc/layering.md](doc/layering.md) | 分层规范：六件套职责、依赖规则、BaseDao/TableCodec、sqlbuilder、m_ 查询、事务 |
| [doc/permissions.md](doc/permissions.md) | 权限鉴权：登录/守卫装配、权限码声明收集、RBAC 真码链、appCode、验收矩阵 |
| [doc/adding-module.md](doc/adding-module.md) | 新增模块/新表操作手册（六件套清单 + 自检） |

## 路线图

- [x] moon-token 鉴权接入（登录/注销 + 逐路由守卫 + RBAC 真码链 + appCode 多应用，10-03）
- [x] `m_` 动态查询通用件（core/query.mbt，22 用例过）
- [x] 登录密文校验（`md5(密码+盐)` 对齐 boot2，mooncrypt md5 + 单测 3 例，10-04）
- [x] `POST /sys/refreshToken`（rotate 端点，UC-0113 全量轮转 + 登出联动，矩阵 10/10，10-03）
- [ ] 事务模板（参照 jeeflow-moon `MysqlTxTemplate`：环境连接 + 嵌套复用；现为 grant 局部事务）
- [ ] 会话存储文件/Redis 后端（moon-token 端口已预留）
- [ ] `rainbow` 分页导航补齐
- [ ] dev 模块：代码生成器（一次性脚手架产出六件套源码）
- [ ] CI：GitHub Actions（wasm + native 双档）

## License

[Apache-2.0](./LICENSE)
