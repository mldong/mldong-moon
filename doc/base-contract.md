# base-verify 契约跑测 · 差异清单（2026-10-03 首轮）

> 跑批报告：协调仓 `base-verify/reports/2026-10-04-moon-dict-l2.{json,txt}`（字典轮 10/16）。
>
> 用途：对照家族 base 契约 runner（协调仓 `scripts/contract-tests/contract_runner.py`，语言无关纯 HTTP）
> 逐组给出 mldong-moon 的现状——**已存在端点的契约比对结论 + 未存在端点的按模块清单**。
> 未存在的接口按此清单逐模块补齐（等下一步慢慢完善，每补一个模块回来复跑一轮）。

## 1. 怎么跑

```bash
# 起服务（另窗口）
export MLDONG_DB_HOST=... MLDONG_DB_PWD=... MLDONG_DB_NAME=mldong-moon
moon run --target wasm cmd/main     # 默认 127.0.0.1:18680

# 契约 runner（协调仓根；16 组用例，本仓只读 5 组 + 缺模块 11 组）
python scripts/contract-tests/contract_runner.py \
  --base-url http://127.0.0.1:18680 --user-name superAdmin --password 123456 \
  --no-redis --with-writes --with-file-upload \
  --report base-verify/reports/2026-10-03-moon-l2.json
```

## 2. 最新结果（2026-10-04 字典轮：**10 pass / 6 fail**，fail 全部是 404 缺模块）

| 用例组 | 端点 | 结果 | 说明 |
|---|---|---|---|
| UC-0101/0102/0112 | /sys/getCaptchaOpenFlag, /sys/user/info, /sys/user/permCode | ✅ pass | 验证码开关（`data.flag` 布尔）、个人中心 8 键（含 deptName/lastLoginTime）、permCode string[]、公开端点忽略坏 Bearer、坏 token 99990403 |
| UC-0113 | /sys/refreshToken | ✅ pass | 全量轮转：新对≠旧对、旧 access 99990403、重放 99990410、二轮轮转、垃圾串负向 |
| UC-0209/0211 | /sys/user/onlineUserList | ✅ pass | 表格 + 详情弹窗字段齐 |
| UC-0405 | /sys/role/page | ✅ pass | 分页五字段 + 行 id(str)/name/code |
| UC-0417 | /sys/config/page | ✅ pass | 分页五字段 |
| UC-0610 | /app/appVersion/check | ❌ 404 | app 模块整缺 |
| UC-0303/0306/0310 | /dev/schema/page, /dev/schema/getByTableName | ❌ 404 | dev_schema 前端生成元数据模型整缺（见 §4 说明） |
| UC-0409 | /sys/menu/tree | ❌ 404 | menu 模块整缺 |
| UC-0411/0413 | /sys/dict/page, /sys/dict/getByDictType | ✅ pass（10-04） | getByDictType 直返 `[{label,value}]`、dataType coerce、未知类型空数组 |
| UC-0431 | /sys/dict/enumDictList | ✅ pass（10-04） | 枚举注册表 yes_no，dataType 整型码表；getByDictType 出口无 dataType 键 |
| UC-0432 | /sys/dict/customDictList | ✅ pass（10-04） | 基础仓零实现空清单，两域分离 ∩ = ∅ |
| UC-0430 | /sys/dictItem/page（m_ 通用查询 13 操作符） | ✅ pass（10-04） | 全 13 操作符 + keywords/orderBy 白名单 + 漏传全量 |
| UC-0426 | /sys/dict/save|update + ext↔variable i18n 链 | ✅ pass（10-04） | 双读侧逐键往返；不带 ext / ext={} / NULL 存量三态均不出键（dept/post 同步统一） |
| UC-0501 | /sys/message/page | ❌ 404 | message 模块整缺 |
| UC-0601/0602/0606 | /sys/fileInfo/upload, getFileInfoByIds, remove | ❌ 404 | file 模块整缺 |
| UC-0608 | /sse/events | ❌ 404 | SSE 整缺（首帧 `{userId,type:"init",msg}`） |

报告存档：协调仓 `base-verify/reports/2026-10-03-moon-l2.{json,txt}`。

## 3. 本轮顺手修掉的契约差异（已存在端点）

1. **鉴权失败 HTTP 恒 200，业务码进信封**——boot2 GlobalExceptionHandler 返 CommonResult /
   goframe `WriteJson(base.Fail(...))` 都是 200；vben5 按 `code` 分支不吃 HTTP 状态。
   moon 原来 401/403 直出 HTTP 状态，已改（`core-web/guard.mbt` on_error + login/logout fail_auth）。
2. **受保护端点 token 失败 = 99990403**（boot2 NotLoginException→TOKEN_NOT_EXIST、goframe 同码）；
   `99990401` 只归登录端点「用户名或密码错误」。e2e 四处断言同步改（D3/RR4/C11/U24）。
3. **补 `/sys/getCaptchaOpenFlag`**（boot2 AuthController 同位）：`data.flag` 布尔，
   读链 `MOLE_CAPTCHA_OPEN` env 优先 → sys_config 表 → 默认 false（`ConfigHolder::get_bool`）。
4. **/sys/user/info 补 `deptName` + `lastLoginTime`**（vben5 个人中心消费键）：
   deptName 按 dept_id 实时补查（boot2 loginHandler.postLogin 同位）；
   lastLoginTime = 当前 token 的登录时刻（boot2 `new Date(loginTimestamp)` 同物，moon-token 索引直读）。

## 4. 未存在接口 · 按模块清单（后续补齐顺序建议）

| 模块（表） | runner 消费的端点 | 备注 |
|---|---|---|
| **sys_menu**（菜单） | `/sys/menu/tree` | UC-0409；menu 同时是权限码链数据源（rbac provider 已消费 sys_menu.code，表已在 schema，缺 CRUD/tree 端点） |
| **sys_message**（站内信） | `/sys/message/page` | UC-0501；分页五字段 + 行按前端消费口径 |
| **sys_file_info**（文件） | `/sys/fileInfo/{upload,getFileInfoByIds,remove}` | UC-0601/0602/0606：upload 返 `{url,fileInfoId}`（id 字符串）、回查 `{id,uid,name,url,status}` |
| **app 模块**（APP 检查升级） | `/app/appVersion/check` | UC-0610：免登录、不查库、转调蒲公英自比较 `buildVersionNo`、任何失败降级 `data:null`（家族 13 栈 2026-09-20 已全量对齐，goframe `fd88b94` 为基准） |
| **dev_schema 模型**（前端生成元数据） | `/dev/schema/page`（行含 `{id,tableName,ext,variable}`）、`/dev/schema/getByTableName?tableName=`（含 `columns:[{id,schemaId,fieldName,component,sort,ext}]`） | 注意：家族的 /dev/schema/* 服务的是 **dev_schema/dev_schema_column 两张台账表**（前端代码生成的注册模型，列带 component/ext）；本仓现 `/dev/schema/dbTable`+`/dev/schema/column/list` 是直查 information_schema 的裸元数据切面，**不是同一契约面**——补 dev_schema 台账时两者可并存（裸切面给 gen 后端用，台账面给前端生成用） |
| **SSE** | `/sse/events` | UC-0608：text/event-stream + 首帧 `data:{userId,type:"init",msg}`；站内信已读提醒等前端实时面依赖它 |

## 5. 已记录的语义差异（不拦 runner，记账待议）

- **无权限码**：boot2 NotPermissionException → 99990406 NO_RESOURCE_AUTH；moon 暂同 99990403
  （runner 未测该支，superAdmin 全通行；补 menu 模块后建议对齐 99990406）。
- **登录失败码**：家族各栈本就不一（boot2 10000001 / goframe gerror 默认 50 / moon 99990401）——
  vben5 只看 code≠0 + msg，不构成契约破坏；保持 99990401。
- **时间格式**：moon 统一 UTC（`format_unix_utc`），boot2 用服务器时区；runner 只断键存在不断时区。
