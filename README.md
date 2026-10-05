# mldong-moon

mldong 快速开发框架的 **MoonBit 语言实现**（第 14 栈），与 mldong 框架家族（Java boot2/boot3/boot4、Go、Rust、Python、Node、PHP、C# 等 13 个栈）保持**接口契约一致**：同样的 URL、同样的 `{"code":0,"msg":"..","data":..}` 信封、同样的分页形状与权限码——前端（vben5）与移动端零改动切换后端栈。

**特性**：

- **全链管理面**：用户/角色/部门/岗位/配置/字典/菜单七大全链 CRUD + 授权（角色-菜单、用户-角色、数据范围）、锁定/踢人下线、扮演登录、图形验证码、在线用户
- **低代码底座**：通用下拉 `/{module}/{table}/select` + 动态表网关 + 代码生成器（读活库元数据产 CRUD 六件套源码）
- **配套能力**：站内信（多端隔离 + SSE 实时推送）、文件上传、操作/访问日志、短信（模板渲染）、定时任务、任务队列/历史
- **工程化**：黑盒 e2e 回归矩阵（真库 370 用例）+ 家族契约 runner（16 组）+ 雪花 ID 全链字符串化（防 JS 精度丢失）

> 定位说明：本仓同时是 mldong 家族代码生成器的**模板骨架**——新增表/模块的写法以 `modules/sys` 为准。

## 技术栈

| 项 | 选型 | 说明 |
|---|---|---|
| 语言 | MoonBit（moon 0.1.x + moonc v0.10.x） | 目标档位 wasm（moonrun 执行）；native 档待 CI 接入后验证 |
| Web | [moonback](https://github.com/moonbitlang/moonback) 0.8.6 | 路由/中间件/请求响应 |
| 权限认证 | [mldong/moon-token](https://github.com/mldong/moon-token) 0.1.10 | 登录态/会话/RBAC 标准件（逐路由守卫 + 供数端口 + extra 会话属性） |
| 表单校验 | [moon_zod](https://github.com/Betterlol/moon_zod) 0.8.2 | strip 模式（未声明字段丢弃） |
| 数据库 | MySQL 5.7+，[moondb + moonmysql](https://github.com/moonbitstack/moonorm)（moonbitstack/moonorm monorepo）0.2/0.7.3 | 手写 SQL（六件套分层，见 [doc/layering.md](doc/layering.md)） |

## 快速开始

**环境要求**：Git Bash（Windows）或 bash；MySQL 5.7+；[MoonBit 工具链](https://docs.moonbitlang.com)（官方安装：PowerShell 执行 `irm https://cli.moonbitlang.com/install/powershell.ps1 | iex`，Linux/macOS 用官网 unix 脚本；本机便携装于 `G:\dev-tools\moon` 时见下方备注）。

```bash
# 1. 工具链（官方安装脚本会配好环境；本机便携装则手动：
#    export MOON_HOME=/g/dev-tools/moon PATH=/g/dev-tools/moon/bin:$PATH
#    —— Git Bash 必须用 /g/ 盘符写法，G:/ 解析不到 .exe）

# 2. 建库（一条命令：建库 + 全表 + 种子；中文 COMMENT 记得 utf8mb4）
mysql -u root -p --default-character-set=utf8mb4 < doc/sql/mysql-schema-all.sql

# 3. 配置（密码必须走环境变量，默认值不含密码）
export MLDONG_DB_HOST=127.0.0.1 MLDONG_DB_PORT=3306
export MLDONG_DB_USER=root MLDONG_DB_PWD=<密码> MLDONG_DB_NAME=mldong-moon

# 4. 启动（默认 127.0.0.1:18680）
moon run --target wasm cmd/main
```

**验证**：

```bash
# 登录（种子账号 superAdmin/123456）
curl -s -X POST http://127.0.0.1:18680/sys/login \
  -H 'Content-Type: application/json' \
  -d '{"userName":"superAdmin","password":"123456"}'

# 带 token 打受保护端点（Windows Git Bash 传中文 body 用 --data-binary @file.json，
# 内联中文会被 GBK 弄坏报 99990001）
curl -s -X POST http://127.0.0.1:18680/sys/user/page \
  -H "Authorization: Bearer <token>" -H 'Content-Type: application/json' \
  -d '{"pageNum":1,"pageSize":10}'

# 类型检查 / 回归矩阵（十六套 370 用例，真库）
moon check
BASE=http://127.0.0.1:18680 bash e2e/run.sh
```

## 目录结构

```
mldong-moon/
├── core/           # 框架无关底座：错误码/信封/SQL builder/m_ 动态查询/雪花 ID/配置 Holder
├── core-web/       # moonback 适配层（全工程 web 依赖唯一收口）
├── modules/sys/    # 系统管理（六件套样板：entity/dto/dao/repository/service/controller）
├── modules/dev/    # 低代码台账三件套 + 库元数据底座
├── modules/app/    # APP 检查升级
├── cmd/main/       # 装配入口（鉴权 + 模块挂载 + listen :18680）
├── cmd/gen/        # 代码生成器（读活库元数据产六件套源码）
├── e2e/            # 黑盒回归矩阵（run.sh 总入口）
└── doc/            # 深入文档（见下表）
```

## 文档

| 文档 | 内容 |
|---|---|
| [doc/layering.md](doc/layering.md) | 分层规范：六件套职责、依赖硬规则、BaseDao/sqlbuilder、m_ 动态查询（**改代码前必读**） |
| [doc/api.md](doc/api.md) | 接口文档：全部端点 + 权限码 + 行为语义 |
| [doc/permissions.md](doc/permissions.md) | 权限鉴权：moon-token 集成、RBAC 码链、appCode 多应用（碰登录/权限必读） |
| [doc/adding-module.md](doc/adding-module.md) | 新增模块/新表操作手册（gen 首选路 + 自检清单） |
| [doc/gen-metadata.md](doc/gen-metadata.md) | 代码生成器与元数据底座 |
| [doc/base-contract.md](doc/base-contract.md) | 家族契约 runner 跑法 + 与 boot2 的端点比对结论 |
| [AGENTS.md](AGENTS.md) | AI 协作须知（关键坑清单 + 协作约定） |

## 代码生成

```bash
# 读活库 information_schema 产六件套源码（repository 双文件，共 7 个），拷进 modules/<模块>/ 对应包目录再接线
export MLDONG_DB_* && moon run --target wasm cmd/gen/main -- <表名>...
```

生成面 = 标准 CRUD 五端点 + 权限码片段 + check_unique/find_by_ids；详细流程与自检清单见 [doc/adding-module.md](doc/adding-module.md)，生成器实现见 [doc/gen-metadata.md](doc/gen-metadata.md)。

## 路线图

**里程碑**：sys 全链管理面 → 字典/菜单/RBAC 授权 → message/fileInfo/APP 检查/SSE（家族契约 runner 首批 16/16 收口）→ 低代码三路由 + 日志/短信/定时任务/任务队列 + 扮演往返（10-05，e2e 370/370 + runner 16/16 全绿）。

**计划中**：

- [ ] 登录/登出写 vis_log 行（boot2 切面语义等价物）
- [ ] 短信真通道（provider SPI；现为 mock 渲染直落日志）
- [ ] 事务模板（环境连接 + 嵌套复用；现为 grant 局部事务）
- [ ] 会话存储文件/Redis 后端（moon-token 端口已预留）
- [ ] `rainbow` 分页导航补齐
- [ ] CI：GitHub Actions（wasm + native 双档）

## License

[Apache-2.0](./LICENSE)
