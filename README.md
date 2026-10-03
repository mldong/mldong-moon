# mldong-moon

mldong 快速开发框架的 **MoonBit 栈**实现（第 14 栈）。目标是与既有 13 栈（boot2/3/4、fastapi、flask、django、nestjs、laravel、goframe、gin、hertz、salvo、csharp）保持接口契约一致：同样的 URL、同样的 `{"code":0,"msg":"..","data":..}` 信封、同样的分页形状。

当前是**骨架阶段**：`sys_user` 的增删改查五个端点，作为后续模块（与代码生成器）的模板骨架。

## 技术栈

| 件 | 选型 | 说明 |
|---|---|---|
| Web 框架 | [moonbitlang/moonback](https://github.com/moonbitlang/moonback) 0.8.6 | MoonBit 官方 Web 框架 |
| 权限认证 | [mldong/moon-token](https://github.com/mldong/moon-token) 家族 | 登录态/会话/RBAC 标准件（骨架暂未挂 guard，下一轮接入） |
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
dao（端口 trait，签名只用 entity/dto）
     │ 实现
     ▼
dao-mysql（手写 SQL + 行映射，moondb+moonmysql 全工程唯一入口）

entity（纯数据 struct） / dto（入参 schema + parse + Req + 出参装配）
```

模块按 `sys`（系统管理）/ `dev`（开发工具）/ `biz`（业务）划分，模块内六件固定：`entity / dto / dao / dao-mysql / service / controller`。

## 模块布局

```
mldong-moon/
├── moon.work                  # members: core / modules/sys / cmd
├── core/                      # mldong/moon-core：错误码、响应信封、分页、Json 取值、时钟、雪花 ID
├── modules/sys/               # mldong/moon-sys
│   ├── entity/                #   sys_user → User（类名去表前缀）
│   ├── dto/                   #   user_dto.mbt：moon_zod schema + parse_* + 出参装配
│   ├── dao/                   #   UserDao 端口 trait
│   ├── dao-mysql/             #   UserMysqlDao：SQL + row_user 按列名映射 + 连接助手
│   ├── service/               #   UserService trait + UserServiceImpl[R]
│   └── controller/            #   五端点注册（wrap 统一错误转信封）
└── cmd/main/                  # 装配：MysqlConfig(env) → dao → service → 路由 → listen
```

## 接口（对齐 mldong 13 栈）

全部 `POST`，请求/响应 `application/json`，HTTP 恒 200，`code=0` 成功：

| 端点 | 入参（节选） | 说明 |
|---|---|---|
| `/sys/user/save` | `{userName, realName, mobilePhone?, sex?, deptId?, remark?}` | 新增（用户名查重，雪花 ID 全部以字符串回传/接收，防 JS 精度丢失） |
| `/sys/user/update` | `{id, userName, realName, ...}` | 修改（未传字段不覆盖，对齐 MyBatis-Plus updateById 语义） |
| `/sys/user/remove` | `{ids: [..]}` | 逻辑删除 |
| `/sys/user/detail` | `{id}` | 单个（id 传字符串） |
| `/sys/user/page` | `{pageNum, pageSize, keywords?, searchKeys?, m_{OP}_{col}?...}` | 分页：m_ 通用查询 13 操作符（EQ/NE/GT/GE/LT/LE/LIKE/NLIKE/LLIKE/RLIKE/BT/IN/NIN），3 段/4 段（带表别名，如 `m_t_LIKE_userName`）；列名 camelCase 自动转 snake_case，空值跳过、非法操作符跳过、列名形状白名单防注入；keywords+searchKeys 多列 OR 关键字 |

错误码（骨架子集，码表对齐 13 栈契约后续校准）：`99990000` 内部错误 / `99990001` 参数校验失败 / `99990002` 数据不存在 / `99990003` 业务冲突 / `99990004` 业务失败。

## 快速启动

前置：[MoonBit 工具链](https://docs.moonbitlang.com)（moon + moonrun），MySQL 5.7+/8.0，库名 `mldong-moon`（表结构可参考 mldong-boot2 的 `doc/sql/mldong-plus1.0.sql`，`sys_user` 一张表即可跑通）。

```bash
export MLDONG_DB_HOST=127.0.0.1 MLDONG_DB_PORT=3306
export MLDONG_DB_USER=root   MLDONG_DB_PWD=<你的密码>   MLDONG_DB_NAME=mldong-moon

moon run --target wasm cmd/main     # 默认 127.0.0.1:18680

curl -X POST http://127.0.0.1:18680/sys/user/page \
  -H "Content-Type: application/json" \
  -d '{"pageNum":1,"pageSize":10}'
```

## 路线图

- [ ] 接入 moon-token guard（逐路由守卫 + 登录端点，权限码已按 13 栈预留）
- [ ] 错误信封全局转换层完善（当前为 wrap 骨架版）
- [ ] 事务模板（参照 jeeflow-moon `MysqlTxTemplate`：环境连接 + 嵌套复用）
- [x] `m_` 动态查询通用件（core/query.mbt，10-03 落地，22 用例过）
- [ ] `rainbow` 分页导航补齐
- [ ] dev 模块：代码生成器（一次性脚手架产出六件套源码）
- [ ] CI：GitHub Actions（wasm + native 双档）

## License

[Apache-2.0](./LICENSE)
