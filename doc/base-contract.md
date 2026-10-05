# base-verify 契约跑测 · 差异清单（2026-10-03 首轮）

> 跑批报告：**`base-verify/reports/2026-10-05-moon-batch12-l2.json`（sys/dev 按需增补轮 16/16 全绿保持）**；历史：`base-verify/reports/2026-10-04-moon-dict-l2.{json,txt}`（字典轮 10/16）、`base-verify/reports/2026-10-04-moon-menu-l2.{json,txt}`（菜单轮 11/16）、`base-verify/reports/2026-10-04-moon-menu2-l2.json`（菜单缺口补齐轮 11/16 无回归）、`base-verify/reports/2026-10-05-moon-dev-l2.json`（dev 台账轮 **12/16**，UC-0303/0306/0310 收口）、`base-verify/reports/2026-10-05-moon-final-l2.json`（**收口轮 16/16 全绿**：message/fileInfo/appversion/sse 四模块落地——base 首批契约全部收口）。boot2 全量 12 端点已对齐（syncRoute 无 base 契约，仓内 e2e 隔离域覆盖）；dev 模块 boot2 22 端点已对齐（无 base 契约的进仓内 e2e matrix_dev 55 例）。
>
> 用途：对照家族 base 契约 runner（协调仓 `scripts/contract-tests/contract_runner.py`，语言无关纯 HTTP）
> 逐组给出 mldong-moon 的现状——**已存在端点的契约比对结论 + 未存在端点的按模块清单**。
> 未存在的接口按此清单逐模块补齐（等下一步慢慢完善，每补一个模块回来复跑一轮）。

## 1. 怎么跑

```bash
# 起服务（另窗口）
export MLDONG_DB_HOST=... MLDONG_DB_PWD=... MLDONG_DB_NAME=mldong-moon
moon run --target wasm cmd/main     # 默认 127.0.0.1:18680

# 契约 runner（协调仓根；16 组用例全量覆盖）
python scripts/contract-tests/contract_runner.py \
  --base-url http://127.0.0.1:18680 --user-name superAdmin --password 123456 \
  --no-redis --with-writes --with-file-upload \
  --report base-verify/reports/2026-10-03-moon-l2.json
```

## 2. 最新结果（2026-10-05 收口轮：**16 pass / 0 fail** 全绿）

| 用例组 | 端点 | 结果 | 说明 |
|---|---|---|---|
| UC-0101/0102/0112 | /sys/getCaptchaOpenFlag, /sys/user/info, /sys/user/permCode | ✅ pass | 验证码开关（`data.flag` 布尔）、个人中心 8 键（含 deptName/lastLoginTime）、permCode string[]、公开端点忽略坏 Bearer、坏 token 99990403 |
| UC-0113 | /sys/refreshToken | ✅ pass | 全量轮转：新对≠旧对、旧 access 99990403、重放 99990410、二轮轮转、垃圾串负向 |
| UC-0209/0211 | /sys/user/onlineUserList | ✅ pass | 表格 + 详情弹窗字段齐 |
| UC-0405 | /sys/role/page | ✅ pass | 分页五字段 + 行 id(str)/name/code |
| UC-0417 | /sys/config/page | ✅ pass | 分页五字段 |
| UC-0610 | /app/appVersion/check | ✅ pass（10-05） | 免登录；platform 越界/缺 versionCode → 99999999 + 具体 msg；未来版本号 → code 0 + data=null（moon 档蒲公英外呼客户端未接恒走降级，三态同判不受影响） |
| UC-0303/0306/0310 | /dev/schema/page, /dev/schema/getByTableName | ✅ pass（10-05） | page 行 id(str)/tableName/ext/variable；getByTableName columns 非空且列含 id(str)/schemaId/fieldName/component/sort/ext（dev_schema 台账全量落地） |
| UC-0409 | /sys/menu/tree | ✅ pass（10-04） | 直返数组、根节点 id(str)/name、children 嵌套、ext 空不出键 |
| UC-0411/0413 | /sys/dict/page, /sys/dict/getByDictType | ✅ pass（10-04） | getByDictType 直返 `[{label,value}]`、dataType coerce、未知类型空数组 |
| UC-0431 | /sys/dict/enumDictList | ✅ pass（10-04） | 枚举注册表 yes_no，dataType 整型码表；getByDictType 出口无 dataType 键 |
| UC-0432 | /sys/dict/customDictList | ✅ pass（10-04） | 基础仓零实现空清单，两域分离 ∩ = ∅ |
| UC-0430 | /sys/dictItem/page（m_ 通用查询 13 操作符） | ✅ pass（10-04） | 全 13 操作符 + keywords/orderBy 白名单 + 漏传全量 |
| UC-0426 | /sys/dict/save|update + ext↔variable i18n 链 | ✅ pass（10-04） | 双读侧逐键往返；不带 ext / ext={} / NULL 存量三态均不出键（dept/post 同步统一） |
| UC-0501 | /sys/message/page | ✅ pass（10-05） | 五字段分页 + 行 id(str)/title/isRead；无权限接口（仅登录）；message 8 端点全落（接收人 + appCode biz_type 前缀端隔离） |
| UC-0601/0602/0606 | /sys/fileInfo/upload, getFileInfoByIds, remove | ✅ pass（10-05） | upload 返 {url,fullUrl,fileInfoId(str)}（multipart 本地盘直写 /uploadfiles/yyyyMM/）；回查逗号串 Ant 形状 {id,uid,name,url,status:done}；remove 物理删 |
| UC-0608 | /sse/events | ✅ pass（10-05） | POST + text/event-stream；首帧 data:{userId,type:"init",msg:"初始化连接成功"}；10s 心跳保活；仅登录无权限码 |

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

## 4. 未存在接口 · 按模块清单（**2026-10-05 全清**——boot2 sys/dev 扫描 + vben5 消费仲裁后按需补齐）

| 模块（表） | runner 消费的端点 | 备注 |
|---|---|---|
| ~~sys_message~~ **已补（10-05）** | `/sys/message/page` | UC-0501；分页五字段 + 行按前端消费口径 |
| ~~sys_file_info~~ **已补（10-05）** | `/sys/fileInfo/{upload,getFileInfoByIds,remove}` | UC-0601/0602/0606：upload 返 `{url,fileInfoId}`（id 字符串）、回查 `{id,uid,name,url,status}` |
| ~~app 模块~~ **已补（10-05，moon 档蒲公英外呼降级见 §2 UC-0610 行）** | `/app/appVersion/check` | UC-0610：免登录、不查库、转调蒲公英自比较 `buildVersionNo`、任何失败降级 `data:null`（家族 13 栈 2026-09-20 已全量对齐，goframe `fd88b94` 为基准） |
| ~~dev_schema 模型~~ **已补（10-05）** | boot2 dev 22 端点全量 | 见下节"dev 模块"行 |
| ~~SSE~~ **已补（10-05）** | `/sse/events` | UC-0608 |
| ~~sys/sys 增补面~~ **已补（10-05 按需增补轮）** | 低代码下拉三路由 + RBAC 授权 7 端点 + 踢人四件套 + captcha 三件套 + dept tree/autoSort/updateSort + dict clearCache + 日志两表 CRUD5 + sms 六面 + timer 内存态 9 端点 + 任务队列/历史 cancel/restore | 仲裁口径：**boot2 sys/dev 全表扫描 → vben5 实际消费 → 按需补**。明确不做（前端零消费）：oauth2、thirdParty/relThirdAccount、machine 信息、notice 孤表、dict generateExportUrl/importTo、querySchema 运行时消费 |

## 5. 已记录的语义差异（不拦 runner，记账待议）

- **无权限码**：boot2 NotPermissionException → 99990406 NO_RESOURCE_AUTH；moon 暂同 99990403
  （menu 模块 10-04 已上线、runner 全绿，vben5 只按 code≠0 分支——**决策：维持 99990403 不对齐**，
  boot2 语义差异记账即可；若将来 vben5 出现"区分 401/403 跳转"需求再启）。
- **登录失败码**：家族各栈本就不一（boot2 10000001 / goframe gerror 默认 50 / moon 99990401）——
  vben5 只看 code≠0 + msg，不构成契约破坏；保持 99990401。
- **时间格式**：moon 统一 UTC（`format_unix_utc`），boot2 用服务器时区；runner 只断键存在不断时区。
- **dict clearCache**：moon 枚举注册表为启动期快照 + 自定义字典请求时派生，无运行期缓存可清——
  端点幂等空响应保持契约形状（boot2 清 Redis 缓存）。
- **扮演（playUser/unPlayUser，10-05 已实现）**：boot2 双会话同构——给目标签真会话（`login(extra)` 盖 isPlayer/playerToken/playerUserId/playUserAccount），unPlay 凭 extra 回跳操作者 token；moon 特有补充：操作者原 access 2h 滑动过期 → extra 存 playerRefreshToken，unPlay 走 `rotate` 兜底换全新对。全部走 moon-token 0.1.9/0.1.10 公开原语，零源码改动；`/sys/user/info` 增 `ext.isPlayer` 投影（vben5 退出扮演入口开关）。剩余差异：moon 对被禁用目标直接拒登（moon-token login 的 ban 检查，boot2 无此步）。
- **SM2 登录加密**：moon 无 sm2 依赖，`/sys/getSm2PublicKey` 恒返空公钥=前端不加密分支（boot2 开关关同形状）。
- **短信通道**：moon 无短信 SDK——sendCode/verifyCode 内存态验证码 + sendNotification/batchSendNotification 模板渲染直落 sys_sms_log（provider=mock）；boot2 走真通道。
- **定时任务**：moon 无 cron 调度器/runner bean——/sys/timer/* 为进程内存态（boot2 TimerCache 同物），executeImmediate 幂等空响应；save/remove 为 moon 补面（vben5 timer.ts 有调、boot2 未暴露）。
- **vis_log 写入**：boot2 切面在登录/登出写 vis_log 行——moon 本轮仅管理面 CRUD5（runner/vben5 均不消费该写入），后续补切面等价物。
- **moonback Trie 路由坑（实现留档）**：put_route 注册模式串时先 search 后 insert——同形静态路由重复注册、或先挂 `/:module/:table/*` 再挂 `/lowCode/:tableName/*` 都会 RouteConflict；必须**先挂带静态前缀的、后挂通配**，且 `/sys/user/select` 专属语义由 user_controller 自带端点承载。
