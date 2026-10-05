# mldong-moon

mldong 快速开发框架的 **MoonBit 语言实现**。目标是与 mldong 框架的接口契约保持一致：同样的 URL、同样的 `{"code":0,"msg":"..","data":..}` 信封、同样的分页形状、同样的权限码与鉴权失败码。

当前已落：`sys_user` 全链 16 端点（CRUD + 状态/个人中心/在线用户/**踢人四件套**）+ `sys_role`/`sys_dept`/`sys_post`/`sys_config` CRUD + **`sys_dict`/`sys_dict_item` 字典全链**（CRUD + getByDictType/enumDictList/customDictList/clearCache）+ **`sys_menu` 菜单全链**（CRUD + tree/list + appList + 用户路由菜单三版 + syncRoute）+ 登录/注销/refreshToken（moon-token 家族 0.1.10）+ **图形验证码三件套**（captcha SVG 手绘 + getCaptchaOpenFlag 登录联动 + getSm2PublicKey 空公钥占位）+ moon-token 鉴权（RBAC 真码链 + appCode 多应用）+ **RBAC 授权面**（saveRoleMenu/roleMenuIds/saveUserRole/removeUserRole/userListByRoleId/Exclude + grantDataScope）+ **扮演往返**（playUser/unPlayUser 双会话同构）+ **部门树/排序**（tree 双码 OR + autoSort + updateSort）+ **通用下拉 lowCode 三路由**（/:module/:table/select + /sys/user/select 专属 + /lowCode 动态表网关，goframe 协议同构：labelKey/valueKey/extFieldNames/includeType 回显/keywords+searchKeys OR-LIKE/orderBy 安全解析/真列白名单）+ **日志两表**（opLog/visLog CRUD5，物理删）+ **短信**（smsTemplate/smsLog CRUD5 + sendCode/verifyCode 内存态一次性消费 + sendNotification/batchSendNotification mock 模板渲染）+ **定时任务内存态**（timer 9 端点，boot2 TimerCache 同物）+ **任务队列/历史**（taskExecutionQueue/taskExecutionHistory CRUD5 + cancelTask 转历史 + restore 重排队）+ **站内信**（8 端点：接收人隔离 + appCode biz_type 前缀端隔离 + setRead/未读计数）+ **文件上传**（multipart 本地盘直写 + Ant 形状回查）+ **APP 检查升级**（免登录 UC-0610，蒲公英转调降级语义）+ **SSE 实时推送**（首帧 init + 10s 心跳）+ `dev` 模块 **dev_schema 台账三件套全量**（22 端点 + 4 个 dev 字典枚举入册）。同时是后续模块与代码生成器的**模板骨架**。

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
repository（手写 SQL + 行映射，方言收口 dialect.mbt 的 Conn 缝：换库=新 Box+新工厂分支）

entity（纯数据 struct） / dto（入参 schema + parse + Req + 出参装配）
core（零 web：错误码/信封/sqlbuilder/m_ 查询/雪花）
core-web（moonback 适配：wrap 统一错误转信封 / 守卫工具——全工程 web 依赖唯一收口）
```

模块按 `sys`（系统管理）/ `dev`（开发工具）/ `biz`（业务）划分，模块内六件固定：`entity / dto / dao / repository / service / controller`。

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
│   ├── repository/                #   BaseDao[T] 单表模板 + TableCodec + 手写 join SQL + 方言缝
│   ├── service/               #   UserService trait + Impl[R]；rbac_service.mbt = RBAC + moon-token 供数方
│   ├── controller/            #   端点注册 + policy() 权限码片段（与端点同文件）
│   └── module.mbt             #   模块自注册（main 每模块一行）
├── modules/dev/               # mldong/moon-dev：dev_schema 台账三件套（22 端点，boot2 dev 对齐）+ 库元数据底座（MetadataDao 一件两用：gen 直调 + importTable 导入）
├── modules/app/               # mldong/moon-app：APP 检查升级（免登录 UC-0610；平台字典 env + 降级 data=null）
├── cmd/main/                  # 装配：鉴权（moon-token）+ 模块挂载 + listen :18680
├── cmd/gen/                   # 代码生成器：读活库元数据产六件套源码（产物即手写代码进仓）
└── doc/                       # 深入文档
    ├── layering.md            #   分层规范（六件套、依赖规则、BaseDao、sqlbuilder、m_）
    ├── permissions.md         #   权限鉴权（登录/守卫/RBAC 链/appCode + 验收矩阵）
    ├── adding-module.md       #   新增模块/新表操作手册
    └── sql/mysql-schema-all.sql  # 建库 + 全表 + 种子数据（一条命令）
```

## 接口（对齐 mldong 接口契约）

全部 `POST`，请求/响应 `application/json`，HTTP 恒 200，`code=0` 成功；鉴权端点带 `Authorization: Bearer <token>`。

| 端点 | 权限码 | 说明 |
|---|---|---|
| `/sys/login` | 豁免 | `{userName, password}` → `{token, refreshToken, userId}`；密文校验 `md5(密码+盐)` 对齐 boot2（错密与不存在同话术防枚举，失败 99990401）；会话 extra 带入 appCode/ip/ua |
| `/sys/getCaptchaOpenFlag` | 豁免 | `{flag: bool}`——`MOLE_CAPTCHA_OPEN` env 优先 → sys_config 表 → 默认 false（boot2 AuthController 同位） |
| `/sys/refreshToken` | 豁免 | `{refreshToken}` → 全新 `{token, refreshToken, userId}`（全量轮转：旧 access+旧 refresh 同时失效；失败统一 `99990410` 不泄露原因） |
| `/sys/logout` | 豁免 | 注销当前 token |
| `/sys/user/save` | `sys:user:save` | 新增（用户名查重；不收密码，发默认密码 `123456` + 8 位随机盐，boot2 同机制；雪花 ID 全部字符串出入，防 JS 精度丢失） |
| `/sys/user/update` | `sys:user:update` | 修改（未传字段不覆盖，MyBatis-Plus updateById 语义） |
| `/sys/user/remove` | `sys:user:remove` | 逻辑删除 `{ids:[..]}` |
| `/sys/user/detail` | `sys:user:detail` | 单个 `{id}` |
| `/sys/user/page` | `sys:user:page` | 分页：join dept/post 名称 + m_ 动态条件 + keywords |
| `/sys/user/grantRole` | `sys:user:grantRole` | `{userId, roleIds}` 用户授权角色（全量替换） |
| `/sys/role/{save,remove,update,detail,page}` | `sys:role:*` | 角色 CRUD |
| `/sys/role/grantDataScope` | `sys:role:grantDataScope` | 数据范围授权 `{id,dataScope,deptIdList}`：sys_role.data_scope 直更 + sys_role_dept 全量替换（boot2 RoleController 同位；归拢在 rbac 面） |
| `/sys/user/{locked,unLocked}` | `sys:user:locked` **OR** `sys:user:unLocked` | 批量锁/解锁（双端点共用双码 OR，boot2 SaMode.OR 同构） |
| `/sys/user/resetPassword` | `sys:user:resetPassword` | 批量重置为默认密码（超管跳过） |
| `/sys/user/select` | `sys:user:select` | 下拉选项 `[{label,value}]` |
| `/sys/user/permCode` | 仅登录 | 当前用户权限码数组（守卫快照投影） |
| `/sys/user/info` / `updateInfo` / `updatePwd` / `updateAvatar` | 仅登录 | 个人中心（id 取自登录主体；info 含 `deptName`/`lastLoginTime` 契约键） |
| `/sys/user/onlineUserList` / `onlineDevice` | `sys:user:onlineUserList` / 仅登录 | 在线用户（按人分组带 tokenList/ip/ua/剩余时长，moon-token 会话枚举） |
| `/sys/user/{logoutByTokenValue,kickoutByTokenValue}` | 各自码 | 按 token 强制注销/踢下线（注销=漏斗全清；踢下线=标记 Kicked 拒重入；boot2 同语义） |
| `/sys/user/{logoutByLoginId,kickoutByLoginId}` | 各自码 | 按登录 ID 批量注销/踢下线；无效 token 幂等 0 |
| `/sys/playUser` | `sys:playUser` | 扮演用户（boot2 AuthServiceImpl 同构双会话）：目标存在 + 超管守卫（非超管不能扮演超管）→ 给目标签真会话（extra 盖 isPlayer/playerToken/playerUserId/playUserAccount + 操作者 ip/ua 继承）→ 返 `{userId,token,refreshToken}` 前端就地换 token；Coexist 策略不踢目标既有登录，权限快照 per-token 天然按目标解析；操作者会话原封不动 |
| `/sys/unPlayUser` | 仅登录 | 退出扮演：读当前会话 extra 回跳操作者 token 并登出 played 会话；原 access 已过期（2h 滑动）走存储的 refreshToken rotate 兜底换全新对——moon-token 原语全公开 API，零源码改动 |
| `/sys/user/info` 的 `ext.isPlayer` | —（随 info 返回） | vben5 `fetchUserInfo` 读 `data.ext?.isPlayer` 驱动"退出扮演"入口（boot2 LoginUser.ext 同位）；从会话 extra 投影，非扮演恒 false |
| `/sys/dept/{save,remove,update,detail,page}` | `sys:dept:*` | 部门 CRUD（**gen 生成**） |
| `/sys/dept/list` | `sys:dept:list` | 部门树（parent_id 内存建树，root=0；手写扩展面） |
| `/sys/dept/tree` | `sys:dept:tree` **OR** `sys:role:grantDataScope` | 部门树（boot2 双码 OR：授权数据范围弹窗借道） |
| `/sys/dept/{autoSort,updateSort}` | `sys:dept:{autoSort,updateSort}` | 自动排序（sort=层级×10000+层内 DFS 序×1000，boot2 同式）+ 批量拖拽 `[{id,sort}]` |
| `/sys/post/{save,remove,update,detail,page}` | `sys:post:*` | 岗位 CRUD（**gen 生成**） |
| `/sys/user/getDeptUserTree` | `sys:user:getDeptUserTree` | 部门用户树（部门节点挂用户叶，boot2 DeptUserTreeVO 同形） |
| `/sys/config/{save,remove,update,detail,page}` | `sys:config:*` | 系统配置 CRUD（**gen 生成** + code 唯一） |
| `/sys/config/public` | 豁免 | 公开配置 `{code: content}` map（`PUBLIC%` 前缀且启用；登录页/版权等免登录读，boot2 同位） |
| `/sys/dict/{save,remove,update,detail,page}` | `sys:dict:*` | 字典 CRUD（**gen 生成** + code 全局唯一） |
| `/sys/dict/getByDictType` | 仅登录 | `[{label,value(+ext?)}]` 直返数组：DB（code+enabled）→ 枚举注册表 → 自定义注册表 → 空数组；dataType=2 时 value 转数值；出口不带 id/dataType（UC-0411/0413/0431③） |
| `/sys/dict/enumDictList` / `customDictList` | 仅登录 | 枚举/自定义字典清单（boot2 DictScanner/CustomDictService 同位：注册中心存服务不存模型、请求时派生；dataType 整型 1\|2 或无键，UC-0431/0432）；枚举注册表与 boot2 @DictEnum 的 sys 域 + 基础件逐项对齐（18 个：yes_no/sex + 16 个 sys_*，同 key 同名同码表；wf_*/biz_*/dev_schema_* 随对应模块建再入册）；注册中心 = core `EnumDictRegistry` 框架件（main 建一实例传各模块，ConfigHolder 同链），声明跟模块走（sys 在 `modules/sys/enums/` 子包逐枚举一文件装配期灌入；getByDictType **DB 优先**，枚举只是回退/播种源——纯 SQL 喂种子同样成立） |
| `/sys/dictItem/{save,remove,update,detail,page}` | `sys:dictItem:*` | 字典项 CRUD（**gen 生成** + 父字典存在性 + dict 内 code 唯一；page 带 m_ 全 13 操作符 + keywords/orderBy 白名单，UC-0430） |
| `/sys/menu/{save,remove,update,detail,page}` | `sys:menu:*` | 菜单 CRUD（**gen 生成** + code 全局唯一；type 保留字字段名 menu_type，json 键仍 `type`） |
| `/sys/menu/tree` / `list` | `sys:menu:tree` / `sys:menu:list` | 菜单树/平铺（appCode 缺省取登录上下文、sort 升序建树、孤儿挂回根、children 嵌套 + ext 空不出键，UC-0409） |
| `/sys/menu/appList` | 仅登录 | 应用列表 `[{label,value}]`：字典 `app_list` 域 → 静态回退（boot2 MenuAppCodeEnum） |
| `GET /menu/all` / `/getMenuList` / `/getArtDesignMenu` | 仅登录 | 用户路由菜单（vben5 登录流契约）：enabled + 登录域 + type 1/2，超管全量/非超管 RBAC 菜单 id 链过滤；`name=code` + meta(order/title/icon/link/iframeSrc/hideInMenu〔v2=hideMenu〕/keepAlive/variable 合并)；art 版多 isIframe/authList |
| `/sys/dict/clearCache` | `sys:dict:clearCache` | 清字典缓存：moon 枚举注册表为启动期快照 + 自定义字典请求时派生，无运行期缓存可清——幂等空响应（差异记 base-contract §4） |
| `/sys/menu/syncRoute` | `sys:menu:syncRoute` | 前端路由同步（**域内清理面，慎用**）：递归 upsert（appCode+code 键、isSync=1 才管、深度上限 8）→ 域内删未同步集（is_sync=1 且不在集合）+ role_menu 级联；**空数组短路不删**；e2e 只在隔离 appCode 域测 |
| `/dev/schema/{save,remove,update,detail,page}` | `dev:schema:*` | 数据模型 CRUD（gen 生成 + ext↔variable 空不出键；detail 的 id 实当 tableName 用——boot2 同位，getByTableName 同一解析） |
| `/dev/schema/dbTable` | `dev:schema:dbTable` OR `dev:schema:importTable` | 库表清单（keywords 滤 + **disabled 已导入标记**，[{name,comment,disabled}]） |
| `/dev/schema/importTable` | `dev:schema:importTable` | 导入/同步表结构：先删同名历史再重建 + 表名首段匹配 group.code + 推断器（组件/ext/dataType 枚举 code；is_deleted 列过滤；listKeys 默认全字段） |
| `GET /dev/schema/getByTableName` | 豁免面（handler 三段自校验） | 按 id/表名取模型 VO：token → appId/appSecret（sys_config SCHEMA_APP_ID/SECRET，默认 admin/123456）→ 99990403；凭证链 + DEFAULT_SCHEMA_AUTO_IMPORT=true 时自愈落库；VO 含派生（moduleName/tableCamelName/className/columns 带 fieldCamelName/listSort/searchSort/ext/schemaGroup 聚合，缺分组伪造 id=schema.id+1） |
| `/dev/schema/updateDesigner` | `dev:schema:updateDesigner` | 表单设计保存：update 主表 + 字段全删重插（sort=index+100，事务），返回最新 VO |
| `/dev/schema/{updateListKeys,updateSearchFormKeys}` | 各自权限码；detail 三码 OR 可见 | 列表/搜索键直更（列名白名单） |
| `/dev/schemaGroup/{save,remove,update,detail,page}` | `dev:schemaGroup:*` | 模型分组 CRUD（code 唯一 99990003） |
| `/dev/schemaField/{save,remove,update,detail,page,updateSort}` | `dev:schemaField:*` | 模型字段 CRUD（page 默认 sort,id 升序；remove 物理删——boot2 @TableLogic 注释同语义）+ updateSort 拖拽换位（boot2 算法逐行 port） |
| `/dev/schema/column/list` | `dev:schema:columnList` | 列清单裸切面（信息模式 + gen 字段类型映射；与台账面并存，gen 代码生成器专用） |
| `/sys/message/{save,remove,update,detail,page,setRead,getUnreadCount,getUnreadCountGroupByBizType}` | save/update 挂码，其余仅登录 | 站内信（boot2 8 端点同位）：**接收人隔离**（读写全强制 receiver=当前用户）+ **appCode 端隔离**（biz_type 前缀自动补 + LIKE 过滤，BS/APP 互不可见）；setRead ids 空=本域全部已读；分页 bizTypes 过滤自动补前缀 |
| `/sys/fileInfo/{save,remove,update,detail,page,upload,getFileInfoByIds}` | CRUD 挂码，upload/byIds 仅登录 | 文件（boot2 同位）：upload multipart 本地盘直写 `{MLDONG_UPLOAD_PATH:-./uploadfiles}/yyyyMM/objectId.ext` 返 `{url,fullUrl,fileInfoId}`；getFileInfoByIds 逗号串回查 Ant 形状 `{id,uid,name,url,status:"done"}`；remove 物理删（family 表无 is_deleted 列） |
| `POST /app/appVersion/check` | 免登录（豁免面） | APP 检查升级（UC-0610）：platform 1..3 + versionCode 校验失败 **99999999**（boot2 @Validated 同码）；不查库，蒲公英 `apiv2/app/check` 语义（env `PGYER_API_KEY` + `PGYER_APP_KEY_ANDROID/HARMONYOS/IOS`，真值不进仓库）任何失败降级 `data:null`；**moon 档外呼 HTTP/TLS 客户端未接，恒走降级分支**（moontls 成熟后补真比较） |
| `POST /sys/captcha` | 豁免 | SVG 图形验证码 `{uuid, base64}`：120×40/4 字符（去易混淆 0O1lI）/干扰线噪点随机旋转，内存 TTL 10 分钟、一次性消费、忽略大小写（salvo/gin 家族同款手绘） |
| `POST /sys/getSm2PublicKey` | 豁免 | `{publicKey:""}`——moon 无 SM2 依赖恒空串=前端不加密分支（boot2 开关关同形状，差异记 §4） |
| `/sys/rbac/{saveRoleMenu,roleMenuIds}` | saveRoleMenu / OR 复合 | 角色-菜单授权（`[{roleId,menuId}]` 顶层数组或 `{list:[..]}` 双形状；空补=清空；roleMenuIds 双码 OR boot2 同） |
| `/sys/rbac/{saveUserRole,removeUserRole}` | `sys:rbac:*` | 用户-角色授权对 `[{userId,roleId}]` 逐对增删 |
| `/sys/rbac/{userListByRoleId,userListExcludeRoleId}` | `sys:rbac:*` | 角色下用户分页/排除分页（keywords user_name/real_name OR-LIKE + m_ 叠加） |
| `POST /{module}/{table}/select` | 仅登录 | **通用下拉**（goframe 协议同构）：module+table 拼表名（table 小驼峰→snake）、labelKey/valueKey 缺省 name/id、extFieldNames→ext 嵌套、keywords+searchKeys 多列 OR-LIKE、orderBy 安全解析、includeType 1/2 回显、pageSize 缺省 1000、information_schema 真列白名单 |
| `POST /lowCode/{tableName}/{select,page,detail}` | 仅登录 | lowCode 动态表网关（tableName 完整 snake 表名；page 全字段 snake 键；detail 单行） |
| `/sys/opLog/{save,remove,update,detail,page}` / `/sys/visLog/{...}` | `sys:opLog:*` / `sys:visLog:*` | 操作/访问日志 CRUD5（表无 is_deleted 物理删；写入口=切面族语义，moon 本轮仅管理面，登录写日志行差异记 §4） |
| `/sys/sms/{sendCode,verifyCode}` | 豁免 | 短信验证码：`{phone,bizType}` → `{taskId}`；6 位码内存态（phone:bizType 键 TTL 5 分钟一次性消费）；verify 幂等布尔；落 sys_sms_log provider=mock |
| `/sys/sms/{sendNotification,batchSendNotification}` | `sys:sms:*` | 通知短信：按 biz_type 取启用模板渲染 `{k}` 占位（未配置降级通用文案）落日志；batch 逐 phone 数组回执 `{phone,success,taskId,messageId}`；真通道接入后续轮 |
| `/sys/smsTemplate/{save,remove,update,detail,page}` | `sys:smsTemplate:*` | 模板 CRUD5 + biz_type+provider 唯一前置（uk_biz_type_provider，友好 99990003） |
| `/sys/smsLog/{save,remove,update,detail,page}` | `sys:smsLog:*` | 短信日志 CRUD5（表无 is_deleted/审计列物理删） |
| `/sys/timer/{save,remove,detail,page,stop,start,update,reset,executeImmediate}` | 各自码（stop/start 共用 `sys:timer:stop` boot2 注解同款） | 定时任务内存态（boot2 TimerCache 同物，无表重启即失）：state 1 运行/2 停止；reset redisCron 回落 cron；executeImmediate 幂等（无 runner 可执行，差异记 §4）；save/remove 为 moon 补面（前端 timer.ts 有调 boot2 未暴露） |
| `/sys/taskExecutionQueue/{save,remove,update,detail,page,cancelTask}` | `sys:taskExecutionQueue:*` | 任务队列 CRUD5 + 取消（boot2 TaskExecutionProvider 同语义：队列行转历史 task_state=3 同 id + finishedTime + cancelReason 后删队列行） |
| `/sys/taskExecutionHistory/{save,remove,update,detail,page,restore}` | `sys:taskExecutionHistory:*` | 任务历史 CRUD5 + 恢复（历史行复制为新队列行 state=0 未开始/新雪花 id/variable 兜底 "{}"，历史保留——boot2 同语义） |
| `POST /sse/events` | 仅登录 | SSE 实时推送（UC-0608）：text/event-stream + 首帧 `{userId,type:"init",msg}` + 10s 心跳注释行保活（boot2 SseTaskRunner 同位） |

- 未登录 `HTTP 401 + {"code":99990401}`；无权限 `HTTP 403 + {"code":99990403}`；
- 分页请求 `{pageNum, pageSize, keywords?, searchKeys?, m_{OP}_{col}?...}`，响应 data 形状
  `recordCount/totalPage/pageSize/pageNum/rows`；
- `m_` 通用查询 13 操作符（EQ/NE/GT/GE/LT/LE/LIKE/NLIKE/LLIKE/RLIKE/BT/IN/NIN），
  3 段式 `m_EQ_userName` / 4 段式（带表别名）`m_t_LIKE_userName`；列名 camelCase 自动转
  snake_case，空值跳过、非法操作符跳过、列名形状白名单防注入；
- 错误码（骨架子集，码表对齐 mldong 框架约定）：`99990000` 内部 / `99990001` 参数校验失败 /
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

## 代码生成

新表六件套一条命令产出（读活库 `information_schema`，按列类型/可空/注释渲染）：

```bash
export MLDONG_DB_*   # 同主程序
moon run --target wasm cmd/gen/main -- sys_dept sys_post   # 产出到 gen-out/，拷进模块即接入
```

- 产物 = 手写代码（文件头带〔cmd/gen 生成，可手改〕），非编译期挂钩子；
- 生成面 = 标准 CRUD 五端点 + 权限码片段；**树表/状态机等特性走手写扩展面**（如 dept_tree.mbt，
  独立文件重生成不覆盖）；dto 顶层标识符带表内小写前缀（同包多实体不撞名）；
- 接入三步见 [doc/adding-module.md](doc/adding-module.md)；元数据底座见 [doc/gen-metadata.md](doc/gen-metadata.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | AI 协作入口：结构、工具链、关键坑、上手路线 |
| [doc/layering.md](doc/layering.md) | 分层规范：六件套职责、依赖规则、BaseDao/TableCodec、sqlbuilder、m_ 查询、事务 |
| [doc/permissions.md](doc/permissions.md) | 权限鉴权：登录/守卫装配、权限码声明收集、RBAC 真码链、appCode、验收矩阵 |
| [doc/adding-module.md](doc/adding-module.md) | 新增模块/新表操作手册（六件套清单 + 自检） |
| [doc/gen-metadata.md](doc/gen-metadata.md) | 库元数据底座：跨库实现要点、类型映射、gen/dev_schema 两条消费路 |
| [doc/base-contract.md](doc/base-contract.md) | 家族契约 runner 跑法 + 已存在端点比对结论 + 未存在接口按模块清单 |

## 路线图

- [x] moon-token 鉴权接入（登录/注销 + 逐路由守卫 + RBAC 真码链 + appCode 多应用，10-03）
- [x] `m_` 动态查询通用件（core/query.mbt，22 用例过）
- [x] 登录密文校验（`md5(密码+盐)` 对齐 boot2，mooncrypt md5 + 单测 3 例，10-04）
- [x] `POST /sys/refreshToken`（rotate 端点，UC-0113 全量轮转 + 登出联动，矩阵 10/10，10-03）
- [ ] 事务模板（参照 jeeflow-moon `MysqlTxTemplate`：环境连接 + 嵌套复用；现为 grant 局部事务）
- [ ] 会话存储文件/Redis 后端（moon-token 端口已预留）
- [ ] `rainbow` 分页导航补齐
- [x] dev 模块元数据底座（MetadataDao 端口 + information_schema 实现 + dbTable/column/list 端点，10-04）
- [x] dev 模块 dev_schema 台账三件套全量（boot2 22 端点 + 4 字典枚举 + 种子 2 模型全字段 + 探针表，runner 12/16 UC-0303 组收口，10-05）
- [x] **base 首批契约全收口 16/16**：message 8 端点 + fileInfo 上传链 + app 检查升级 + SSE 推送（e2e 十三套 269/269，10-05）
- [x] **sys/dev 按需增补轮（boot2 扫描 + vben5 消费仲裁）**：通用下拉 lowCode 三路由（goframe 协议同构）+ RBAC 授权面 7 端点（saveRoleMenu/roleMenuIds/saveUserRole/removeUserRole/userListByRoleId|Exclude/grantDataScope）+ 踢人四件套 + captcha 三件套（SVG 手绘 + 登录联动）+ dept tree/autoSort/updateSort + dict clearCache + 日志两表 CRUD5 + 短信六面（模板/日志 CRUD5 + 发送四端点 mock 渲染）+ timer 内存态 9 端点 + 任务队列/历史（cancelTask/restore 往返）——**runner 16/16 保持全绿，e2e 十七套 364/364**（10-05）
- [ ] 登录/登出写 vis_log 行（boot2 切面语义；本轮未做——runner/vben5 均不消费，差异记 base-contract §4）
- [ ] 短信真通道（阿里云/腾讯云 provider SPI；现为 mock 渲染直落日志）
- [x] **扮演往返（playUser/unPlayUser）**：boot2 双会话同构（目标真会话 + extra 盖操作者标记 + unPlay 回跳 + 2h 过期 rotate 兜底）；moon-token 家族依赖升 0.1.10（对 0.1.9 零代码 diff，纯版本轮）；e2e 扮演往返 8 例（10-05）
- [x] 家族契约 runner 首轮：已存在端点 5 组全 pass（认证/refresh/在线/角色页/配置页），缺模块清单见 doc/base-contract.md（10-03）
- [x] 字典模块（sys_dict + sys_dict_item 全链 + getByDictType/enumDictList/customDictList + ext 空不出键统一到 dept/post）：e2e 9 套 142/142 + 契约 runner **10/16 pass**（10-04）
- [x] 菜单模块（sys_menu CRUD + tree/list + appList + 用户路由菜单三版 + syncRoute 隔离域验证）：e2e 10 套 **178/178** + 契约 runner **11/16 pass**（10-04）
- [ ] 事务模板（参照 jeeflow-moon `MysqlTxTemplate`：环境连接 + 嵌套复用；现为 grant 局部事务）
- [ ] dev 模块：代码生成器（读 MetadataDao 产出六件套源码，见 doc/gen-metadata.md §4）
- [ ] dev_schema 台账（importTable 落库 + disabled 标记 + /dev/schema/page·getByTableName 契约面，boot2 同位）
- [ ] CI：GitHub Actions（wasm + native 双档）

## License

[Apache-2.0](./LICENSE)
