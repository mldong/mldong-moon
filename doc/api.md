# 接口文档（对齐 mldong 接口契约）

除标注 GET 外全部 `POST`，请求/响应 `application/json`，HTTP 恒 200，`code=0` 成功；鉴权端点带 `Authorization: Bearer <token>`。

| 端点 | 权限码 | 说明 |
|---|---|---|
| `/sys/login` | 豁免 | `{userName, password}` → `{token, refreshToken, userId}`；密文校验 `md5(密码+盐)` 对齐 boot2（错密与不存在同话术防枚举，失败 99990401）；会话 extra 带入 appCode/ip/ua |
| `/sys/getCaptchaOpenFlag` | 豁免 | `{flag: bool}`——`MOLE_CAPTCHA_OPEN` env 优先 → sys_config 表 → 默认 false（boot2 AuthController 同位） |
| `/sys/refreshToken` | 豁免 | `{refreshToken}` → 全新 `{token, refreshToken, userId}`（全量轮转：旧 access+旧 refresh 同时失效；失败统一 `99990410` 不泄露原因） |
| `/sys/logout` | 豁免 | 注销当前 token |
| `/sys/user/save` | `sys:user:save` | 新增（用户名查重；不收密码，发默认密码 `123456` + 8 位随机盐，boot2 同机制；雪花 ID 全部字符串出入，防 JS 精度丢失） |
| `/sys/user/update` | `sys:user:update` | 修改（未传字段不覆盖，updateById 语义） |
| `/sys/user/remove` | `sys:user:remove` | 逻辑删除 `{ids:[..]}` |
| `/sys/user/detail` | `sys:user:detail` | 单个 `{id}` |
| `/sys/user/page` | `sys:user:page` | 分页：join dept/post 名称 + m_ 动态条件 + keywords |
| `/sys/user/grantRole` | `sys:user:grantRole` | 用户授权角色，body `{userId, roleIds:[...]}`（全量替换） |
| `/sys/role/{save,remove,update,detail,page}` | `sys:role:*` | 角色 CRUD |
| `/sys/role/grantDataScope` | `sys:role:grantDataScope` | 数据范围授权，body `{id, dataScope, deptIdList:[...]}`：sys_role.data_scope 直更 + sys_role_dept 全量替换（boot2 RoleController 同位；归拢在 rbac 面） |
| `/sys/user/{locked,unLocked}` | `sys:user:locked` **OR** `sys:user:unLocked` | 批量锁/解锁（双端点共用双码 OR，boot2 SaMode.OR 同构） |
| `/sys/user/resetPassword` | `sys:user:resetPassword` | 批量重置为默认密码（超管跳过） |
| `/sys/user/select` | `sys:user:select` | 下拉选项 `[{label,value}]` |
| `/sys/user/permCode` | 仅登录 | 当前用户权限码数组：**每请求现取**（`user_role→role_menu→menu.code`，appCode 取请求域）；超管恒 `["admin"]`（boot2 getPermissionList 同位，前端按它放行全部路由） |
| `/sys/user/info` / `updateInfo` / `updatePwd` / `updateAvatar` | 仅登录 | 个人中心（id 取自登录主体；info 含 `deptName`/`lastLoginTime` 契约键） |
| `/sys/user/onlineUserList` / `onlineDevice` | `sys:user:onlineUserList` / 仅登录 | 在线用户（按人分组带 tokenList/ip/ua/剩余时长，moon-token 会话枚举） |
| `/sys/user/{logoutByTokenValue,kickoutByTokenValue}` | 各自码 | 按 token 强制注销/踢下线：**作用域＝请求里那几枚 token，绝不连坐同账号其它会话**（boot2 `StpUtil.kickoutByTokenValue` 同位）。moon 现按枚走 `logout(token)`——moon-token 的 `kickout(login_id, device=)` 是**账号+设备整族**打墓碑，而登录端点 device 恒 "pc"，用它踢一枚会误伤其它会话（L3 B02 实测）；代价＝被踢方拿到的是笼统未登录而非 `KickedOut` 精确原因，要兼得需 moon-token 补一个按枚 kick 口 |
| `/sys/user/{logoutByLoginId,kickoutByLoginId}` | 各自码 | 按登录 ID 批量注销/踢下线；无效 token 幂等 0 |
| `/sys/playUser` | `sys:playUser` | 扮演用户，body `{userId}`（boot2 AuthServiceImpl 同构双会话）：目标存在 + 超管守卫（非超管不能扮演超管）→ 给目标签真会话（extra 盖 isPlayer/playerToken/playerUserId/playUserAccount + 操作者 ip/ua 继承）→ 返 `{userId,token,refreshToken}` 前端就地换 token；Coexist 策略不踢目标既有登录，权限快照 per-token 天然按目标解析；操作者会话原封不动 |
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
| `/sys/dict/clearCache` | `sys:dict:clearCache` | 清字典缓存：moon 枚举注册表为启动期快照 + 自定义字典请求时派生，无运行期缓存可清——幂等空响应（差异记 [base-contract.md](base-contract.md) §5） |
| `/sys/menu/syncRoute` | `sys:menu:syncRoute` | 前端路由同步（**域内清理面，慎用**）：递归 upsert（appCode+code 键、isSync=1 才管、深度上限 8）→ 域内删未同步集（is_sync=1 且不在集合）+ role_menu 级联；**空数组短路不删**；e2e 只在隔离 appCode 域测 |
| `/dev/schema/{save,remove,update,detail,page}` | `dev:schema:*` | 数据模型 CRUD（gen 生成 + ext↔variable 空不出键；detail 的 id 实当 tableName 用——boot2 同位，getByTableName 同一解析） |
| `/dev/schema/dbTable` | `dev:schema:dbTable` OR `dev:schema:importTable` | 库表清单（keywords 滤 + **disabled 已导入标记**，[{name,comment,disabled}]） |
| `/dev/schema/importTable` | `dev:schema:importTable` | 导入/同步表结构：先删同名历史再重建 + 表名首段匹配 group.code + 推断器（组件/ext/dataType 枚举 code；is_deleted 列过滤；listKeys 默认全字段） |
| `GET /dev/schema/getByTableName` | 豁免面（handler 三段自校验） | 按 id/表名取模型 VO：token → appId/appSecret（sys_config SCHEMA_APP_ID/SECRET，默认 admin/123456）→ 99990403；凭证链 + DEFAULT_SCHEMA_AUTO_IMPORT=true 时自愈落库；VO 含派生（moduleName/tableCamelName/className/columns 带 fieldCamelName/listSort/searchSort/ext/schemaGroup 聚合，缺分组伪造 id=schema.id+1） |
| `/dev/schema/updateDesigner` | `dev:schema:updateDesigner` | 表单设计保存：update 主表 + 字段全删重插（sort=index+100，事务），返回最新 VO |
| `/dev/schema/{updateListKeys,updateSearchFormKeys}` | 各自权限码；detail 三码 OR 可见 | 列表/搜索键直更（列名白名单） |
| `/dev/schemaGroup/{save,remove,update,detail,page}` | `dev:schemaGroup:*` | 模型分组 CRUD（code 唯一 99999999） |
| `/dev/schemaField/{save,remove,update,detail,page,updateSort}` | `dev:schemaField:*` | 模型字段 CRUD（page 默认 sort,id 升序；remove 物理删——boot2 @TableLogic 注释同语义）+ updateSort 拖拽换位（boot2 算法逐行 port） |
| `/dev/schema/column/list` | `dev:schema:columnList` | 列清单裸切面（信息模式 + gen 字段类型映射；与台账面并存，gen 代码生成器专用） |
| `/sys/message/{save,remove,update,detail,page,setRead,getUnreadCount,getUnreadCountGroupByBizType}` | save/update 挂码，其余仅登录 | 站内信（boot2 8 端点同位）：**接收人隔离**（读写全强制 receiver=当前用户）+ **appCode 端隔离**（biz_type 前缀自动补 + LIKE 过滤，BS/APP 互不可见）；setRead ids 空=本域全部已读；分页 bizTypes 过滤自动补前缀 |
| `/sys/fileInfo/{save,remove,update,detail,page,upload,getFileInfoByIds}` | CRUD 挂码，upload/byIds 仅登录 | 文件（boot2 同位）：upload multipart 本地盘直写 `{MLDONG_UPLOAD_PATH:-./uploadfiles}/yyyyMM/objectId.ext` 返 `{url,fullUrl,fileInfoId}`；getFileInfoByIds 逗号串回查 Ant 形状 `{id,uid,name,url,status:"done"}`；remove 物理删（family 表无 is_deleted 列） |
| `/sys/fileInfo/initiateMultipartUpload` | 仅登录 | 分片初始化（UC-0604）：入参 `{size,originalFilename,contentType?,objectType?}`，返 `{fileInfoId(str),uploadId}`；**url 这一步就写入台账**（本地盘有确定性地址）；表无 upload_id 列 ⇒ 会话号落 `attr` JSON |
| `/sys/fileInfo/uploadPart` | 仅登录 | 单枚分片落盘（multipart 表单：file/partNumber/fileInfoId），暂存 `{root}/.multipart/{uploadId}/part_{n:05d}`；同序号重写＝覆盖（台账序号不追加出两份） |
| `/sys/fileInfo/completeMultipartUpload` | 仅登录 | 合并（UC-0605）：**按 partNumber 排序**拼接（不看到达序）→ 回写真实 size/sizeInfo → 清暂存；返 `{fullUrl,url,fileInfoId}`；一片未传就 complete → 业务失败 |
| `/sys/fileInfo/abortMultipartUpload` | 仅登录 | 取消：清暂存 + 删台账行（不留平台侧残留）；对已删行重复取消＝`99990002`，不静默假成功 |
| `POST /app/appVersion/check` | 免登录（豁免面） | APP 检查升级（UC-0610）：platform 1..3 + versionCode 校验失败 **99999999**（boot2 @Validated 同码）；不查库，蒲公英 `apiv2/app/check` 语义（env `PGYER_API_KEY` + `PGYER_APP_KEY_ANDROID/HARMONYOS/IOS`，真值不进仓库）任何失败降级 `data:null`；**moon 档外呼 HTTP/TLS 客户端未接，恒走降级分支**（moontls 成熟后补真比较） |
| `POST /sys/captcha` | 豁免 | SVG 图形验证码 `{uuid, base64}`：120×40/4 字符（去易混淆 0O1lI）/干扰线噪点随机旋转，内存 TTL 10 分钟、一次性消费、忽略大小写（salvo/gin 家族同款手绘） |
| `POST /sys/getSm2PublicKey` | 豁免 | `{publicKey:""}`——moon 无 SM2 依赖恒空串=前端不加密分支（boot2 开关关同形状，差异记 [base-contract.md](base-contract.md) §5） |
| `/sys/rbac/{saveRoleMenu,roleMenuIds}` | saveRoleMenu / OR 复合 | 角色-菜单授权：saveRoleMenu body `[{roleId, menuId}]` 顶层数组或 `{list:[..]}` 双形状（空补=清空）；roleMenuIds body `{roleId}` 回读菜单 id 数组 |
| `/sys/rbac/{saveUserRole,removeUserRole}` | `sys:rbac:*` | 用户-角色授权对，body `[{userId, roleId}]` 逐对增删（兼容 `{list:[..]}` 包裹形状） |
| `/sys/rbac/{userListByRoleId,userListExcludeRoleId}` | `sys:rbac:*` | 角色下用户分页/排除分页（body `{roleId, pageNum, pageSize, keywords?, m_*?}`；keywords user_name/real_name OR-LIKE + m_ 叠加） |
| `POST /{module}/{table}/select` | 仅登录 | **通用下拉**（goframe 协议同构）：module+table 拼表名（table 小驼峰→snake）、labelKey/valueKey 缺省 name/id、extFieldNames→ext 嵌套、keywords+searchKeys 多列 OR-LIKE、orderBy 安全解析、includeType 1/2 回显、pageSize 缺省 1000、information_schema 真列白名单 |
| `POST /lowCode/{tableName}/{select,page,detail}` | select 仅登录；**page/detail 带表名权限码** | lowCode 动态表网关（tableName 完整 snake 表名）。行出口**一律 camelCase**（UC-0318/0319，列名由后端转，前端不兼容 snake）；权限码 `lowCode:{tableName}:page`（detail 与 page 为 OR），因码里带路径参数、Guard 静态策略表达不了，在处理器内按 `require_lowcode_perm` 自查（超管豁免） |
| `/sys/opLog/{save,remove,update,detail,page}` / `/sys/visLog/{...}` | `sys:opLog:*` / `sys:visLog:*` | 操作/访问日志 CRUD5（表无 is_deleted 物理删；写入口=切面族语义，moon 本轮仅管理面，登录写日志行差异记 [base-contract.md](base-contract.md) §5） |
| `/sys/sms/{sendCode,verifyCode}` | 豁免 | 短信验证码：`{phone,bizType}` → `{taskId}`；6 位码内存态（phone:bizType 键 TTL 5 分钟一次性消费）；verify 幂等布尔；落 sys_sms_log provider=mock |
| `/sys/sms/{sendNotification,batchSendNotification}` | `sys:sms:*` | 通知短信：按 biz_type 取启用模板渲染 `{k}` 占位（未配置降级通用文案）落日志；batch 逐 phone 数组回执 `{phone,success,taskId,messageId}`；真通道接入后续轮 |
| `/sys/smsTemplate/{save,remove,update,detail,page}` | `sys:smsTemplate:*` | 模板 CRUD5 + biz_type+provider 唯一前置（uk_biz_type_provider，友好 99999999） |
| `/sys/smsLog/{save,remove,update,detail,page}` | `sys:smsLog:*` | 短信日志 CRUD5（表无 is_deleted/审计列物理删） |
| `/sys/timer/{save,remove,detail,page,stop,start,update,reset,executeImmediate}` | 各自码（stop/start 共用 `sys:timer:stop` boot2 注解同款） | 定时任务内存态（boot2 TimerCache 同物，无表重启即失）：state 1 运行/2 停止；reset redisCron 回落 cron；executeImmediate 幂等（无 runner 可执行，差异记 [base-contract.md](base-contract.md) §5）；save/remove 为 moon 补面（前端 timer.ts 有调 boot2 未暴露） |
| `/sys/taskExecutionQueue/{save,remove,update,detail,page,cancelTask}` | `sys:taskExecutionQueue:*` | 任务队列 CRUD5 + 取消（boot2 TaskExecutionProvider 同语义：队列行转历史 task_state=3 同 id + finishedTime + cancelReason 后删队列行） |
| `/sys/taskExecutionHistory/{save,remove,update,detail,page,restore}` | `sys:taskExecutionHistory:*` | 任务历史 CRUD5 + 恢复（历史行复制为新队列行 state=0 未开始/新雪花 id/variable 兜底 "{}"，历史保留——boot2 同语义） |
| `POST /sse/events` | 仅登录 | SSE 实时推送（UC-0608）：text/event-stream + 首帧 `{userId,type:"init",msg}` + 10s 心跳注释行保活（boot2 SseTaskRunner 同位） |

- **HTTP 恒 200（含鉴权失败）**，业务码进 body：未登录/token 失效 `99990403`、无权限同 `99990403`、
  `99990401` 只归登录「用户名或密码错误」（boot2 GlobalExceptionHandler 同约定，vben5 按 code 分支）；
- 分页请求 `{pageNum, pageSize, keywords?, searchKeys?, m_{OP}_{col}?...}`，响应 data 形状
  `recordCount/totalPage/pageSize/pageNum/rows`；
- `m_` 通用查询 13 操作符（EQ/NE/GT/GE/LT/LE/LIKE/NLIKE/LLIKE/RLIKE/BT/IN/NIN），
  3 段式 `m_EQ_userName` / 4 段式（带表别名）`m_t_LIKE_userName`；列名 camelCase 自动转
  snake_case，空值跳过、非法操作符跳过、列名形状白名单防注入；
- 错误码（骨架子集，码表对齐 mldong 框架约定）：`99990000` 内部 / `99990001` 参数校验失败 /
  `99990002` 数据不存在 / `99990004` 业务失败 / `99990406` 权限码不足 / `99999999` 参数校验失败与唯一键冲突（@Validated / checkUnique 同码）
  参数校验档（UC-0610 在用）；
- `appCode`：登录头（缺省 `platform`）定会话应用上下文，role/menu 按 `app_code` 双过滤，
  同用户不同 app 会话共存。


> 权限码挂法与鉴权链路见 [permissions.md](permissions.md)；分层与信封语义见 [layering.md](layering.md) §7；
> 端点与 boot2 的比对结论（含差异记账）见 [base-contract.md](base-contract.md)。

