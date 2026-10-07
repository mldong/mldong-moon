# 新增模块 / 新表操作手册

> 本仓是代码生成器的模板骨架——加表/加模块**必须**照 `modules/sys` 的写法。
> **首选路 = 代码生成器**（读活库元数据产出六件套源码——entity/dto/dao/repository×2/service/controller
> 共 7 个文件，一步到位）：
>
> ```bash
> export MLDONG_DB_* && moon run --target wasm cmd/gen/main -- <表名>...
> # 产物落 gen-out/（不入仓），拷进 modules/<模块>/ 对应包目录，再走 ⑧ 注册
> # 注意：gen-out/ 里可能有历史跑批残留（dept/post/config…），只拷本次表名对应的 7 个文件
> # （repository 层产 *_repository.mbt + *_table.mbt 两件）
> ```
>
> 生成面 = 标准 CRUD 五端点 + 权限码片段 + check_unique/find_by_ids；树表/状态机等特性
> **直接改生成物文件**（二次开发即手改——boot2/各栈同做法；生成器默认跳过已存在文件防覆盖，
> `--force` 才整体重生成，重生成前先 diff 自己的手改）。以下手工清单用于理解生成物形状。
> 写完自检 §4。

## 场景 A：现有模块加一张表（最常见）

以"在 sys 模块加 `sys_post`"为例（对照 `sys_user` 的六件套真身）：

### ① 建表 SQL

- 追加进 `doc/sql/mysql-schema-all.sql`（保持"一条命令初始化"约定）；
- Windows 导入带中文 COMMENT 的 DDL 加 `mysql --default-character-set=utf8mb4`——否则注释乱码
  会被 gen 从 information_schema 读进生成物注释（不只是美观问题）；
- 列命名 snake_case；主键 `bigint` 雪花（应用侧生成，不 auto_increment）；
- 常备列：`create_time datetime(3)`、`update_time`、`create_user/update_user`、
  `is_deleted tinyint(1)`（逻辑删）；NOT NULL 列想清楚默认值（NULL 三值逻辑坑见 layering §3.5）。

### ② entity（`entity/post.mbt`）

- `pub(all) struct Post { ... }`——字段对应表列，类名去表前缀；可空列 `Option`；
- 分页有 join 就加只读 struct（如 `PostPageRow`），没有就不加。

### ③ dto（`dto/post_dto.mbt`）

- `PostSaveReq` struct + `save_schema`（moon_zod）；
- **strip 模式坑**：`id` 等不校验但要存活的字段写 `"id": @moon_zod.any().optional()`；
- `parse_save`（schema 校验 → `req_of` 手工提取）、`parse_update`（复用 + 校验 `id > 0`）、
  `parse_page`（pageNum/pageSize 自校验 + `@core.parse_m_params`）；
- 出参 `post_json`（雪花 `jsnow` 字符串化、可空 `jstr/jint`）。

### ④ dao（`dao/post_dao.mbt`）

- `pub(open) trait PostDao`：`insert/update/remove_by_ids/find_by_id` + 业务查询（查重、
  分页 `page(Wrapper, Int, Int) -> (Int, Array[...])`）；
- 签名只用 entity/@core 类型，零 ORM。

### ⑤ repository（`repository/post_table.mbt` + `post_repository.mbt`）

- `TableCodec[Post]`：`name/cols/insert_cols/update_cols/from_row/id_of/del_col/order_col`
  （照抄 `user_table.mbt`；`update_cols` 放"可覆盖列 + update_time"；
  `del_col: Some("is_deleted")`）；
- 行映射 `row_post`（`row_text/row_i64/row_opt_*` 按列名取）；敏感列照常进 `cols`（读面要读），
  「不回显」在 dto 出参装配层做（见 user_table.mbt 头注）；
- `PostRepository::make(config)` + `pub impl @dao.PostDao for PostRepository with ...`
  ——单表 CRUD 直接调 `BaseDao` 方法（`base.mbt`），业务查询手写 SQL 用
  `@core.build_select(...)` + `self.query/query_one`。

### ⑥ service（`service/post_service.mbt`）

- `trait PostService` + `pub(all) struct PostServiceImpl[R] { dao : R }` +
  `pub impl[R : @dao.PostDao] PostService for PostServiceImpl[R] with ...`；
- 纯校验规则抽 `fn validate(req) -> String?` 纯函数（不连库，可 `moon test`）；
- 查重冲突抛 `InvalidParam`（99999999，boot2 checkUnique throwBiz 同码）、不存在抛 `NotFound`；NOT NULL 列给业务默认值。

### ⑦ controller（`controller/post_controller.mbt`）

- `pub fn post_policy() -> @guard.RoutePolicy`——**每个端点一条显式 rule**
  （`sys:post:{save,remove,update,detail,page}`，对齐 mldong 框架约定权限码）；
- `pub fn[...] register_post(ctx, svc, g)`——每端点 `@web.wrap(async fn(request) -> Json raise @core.MldongError {...})`
  + `g.post(ctx, "/sys/post/save", save_handler)`；URL 约定 `/sys/<entity>/{save,remove,update,detail,page}`。

### ⑧ 注册（`module.mbt`）

```moonbit
let post_dao = @repo.PostRepository::make(config)
let post_svc = @svc.PostServiceImpl::{ dao: post_dao }
@ctrl.register_post(ctx, post_svc, g) catch { e => abort("sys 模块 post 路由注册失败: \{e}") }
```

权限码聚合加一行：`@web.merge_policy(@ctrl.user_policy(), @ctrl.role_policy())` →
再并 `@ctrl.post_policy()`（建议顺手改成列表折叠，保持一行一实体）。

## 场景 B：新建一个模块（dev / biz）

1. `modules/<mod>/` 建包骨架：`moon.mod`（`name = "mldong/moon-<mod>"`，deps 对齐 sys 的
   moon.mod）+ 根 `moon.pkg`（imports 抄 `modules/sys/moon.pkg`，按需删）+ 六件套子目录
   （各含 `moon.pkg`，imports 抄 sys 对应子包）；
2. `moon.work` 的 members 加 `"./modules/<mod>"`；
3. 根包 `module.mbt`：`pub fn[S, P] install(config, g, auth, holder, enum_registry) -> @mb.Module { ... }`
   （**函数名必须是 `install`**——`module` 是 MoonBit 保留字，照抄会编译失败）
   （模块内装配 + 注册，抄 `modules/sys/module.mbt`；参数**顺序各模块自定**——dev 是
   `(config, g, holder, enum_registry, auth)`、sys 是 `(config, g, auth, holder, enum_registry)`，
   照抄调用方时以该模块 install 真实签名为准）；
4. `cmd/main` 挂一行：`ctx.use_(@<mod>.install(config, g, auth, holder, enum_registry)) catch { _ => abort(...) }`
   （cmd/main 的 moon.pkg 加 `"mldong/moon-<mod>" @<mod>`——别名自定，别照抄 @dev）；
5. 权限码：新模块自己的 policy 聚合函数导出，main 里 `merge_policy` 并进总策略；
6. **枚举字典**（有业务枚举才做）：模块根包建 `enums/` 子包（moon.pkg import `@core`），
   **逐枚举一文件**（goframe「每枚举一文件 + init() 注册」同位）：每文件 = 业务常量
   （`pub let` snake_case，MoonBit 大写裸标识符是构造器命名空间留不得）+ `all()` 列表；
   `registry.mbt` 用 `@core.int_dict(name, dict_key, vals)` 组 `DictModel` + 导出
   `register_<mod>_enum_dicts(registry)`；`install` 收 `@core.EnumDictRegistry`
   参数并在装配期灌入。sys 的样板见 [../modules/sys/enums/](../modules/sys/enums/)（18 个
   枚举 18 文件 + registry）。main 建全进程一实例传各模块
   （ConfigHolder 同一条传链），dict 的 getByDictType/enumDictList 自动可见；
   **DB 优先**：getByDictType 先查库，枚举只是回退/播种源——纯 SQL 喂
   sys_dict/sys_dict_item 种子同样成立（UC-0431）。

## 自检清单（提交前）

- [ ] `moon check` 0 errors，未引入 [../AGENTS.md](../AGENTS.md) §5 之外的新 warning 类别；
- [ ] URL / 信封 / 分页形状 / 错误码与 mldong 接口契约一致（layering §7）；
- [ ] 所有 id 出入 JSON 都是字符串；HTTP 200 恒定；
- [ ] 每个端点有显式权限码 rule（漏 = 只验登录态）；
- [ ] **新权限码进 `sys_menu` 种子行**（按钮型 type=4，code=权限码）——非超管角色的码链来自
  role_menu→menu.code，superAdmin 走 admin_type 旁路**测不出漏种子**，上线后普通用户必 99990403；
- [ ] 新表进回归：`e2e/` 加 matrix_<域>.py（抄现有套件形状）并挂进 run.sh 循环——
  模板仓的契约面靠它守护；
- [ ] 真库冒烟一轮：login → save → page（含 `m_EQ_xxx` 一发）→ detail → update → remove → 负向；
- [ ] 动了鉴权/RBAC → 复跑 [permissions.md](permissions.md) §7 矩阵；
- [ ] 建表 SQL 已进 `doc/sql/mysql-schema-all.sql`；
- [ ] 文件名带层后缀（`*_dto.mbt`/`*_dao.mbt`/`*_repository.mbt`/`*_table.mbt`/`*_controller.mbt`），
      类名去表前缀，JSON camelCase / DB snake_case。
