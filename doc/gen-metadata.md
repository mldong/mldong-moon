# 库元数据底座（gen 代码生成器 / dev_schema 导入共用）

> mldong 框架各语言实现的 gen 工具都**直读活库元数据**而非前端台账；
> boot2 的网页版生成器另有 dev_schema 台账（`/dev/schema/importTable` 落库）。本仓把"读库元数据"
> 抽成一件两用：gen 代码生成器直接调，dev_schema 导入功能也调——这就是 `modules/dev` 的
> `MetadataDao` 端口 + `metadata-mysql` 实现（已落地，端点 `/dev/schema/dbTable`、
> `/dev/schema/column/list` 冒烟 5/5）。

## 1. 端口形状（零 ORM 零 web，`modules/dev/metadata/metadata.mbt`）

```moonbit
pub(open) trait MetadataDao {
  /// 表清单（keywords 子串滤表名/注释，可空）
  async fn list_tables(Self, String) -> Array[TableMeta] raise @core.MldongError
  /// 列清单（ordinal 序）
  async fn list_columns(Self, String) -> Array[ColumnMeta] raise @core.MldongError
}

pub(all) struct TableMeta { name : String, comment : String }
pub(all) struct ColumnMeta {
  name : String          // 列名 snake_case
  data_type : String     // 原始类型名（varchar/bigint/datetime，方言各自叫法）
  column_type : String   // 完整类型 varchar(64)/bigint(20)
  is_nullable : String   // YES/NO
  default_value : String?
  comment : String
  is_pk : Bool
  extra : String         // auto_increment 等
}
```

映射工具同文件：`column_to_field_type(ColumnMeta) -> String`（列类型 → 实体字段类型）、
`column_is_nullable`（→ Option 与否）。

## 2. 类型映射表（gen 产出六件套的依据，mldong 框架同位）

| data_type | 实体字段类型 | 说明 |
|---|---|---|
| bigint | `Int64` | 雪花主键/外键 |
| int / smallint / mediumint / tinyint | `Int` | 状态位/枚举值 |
| double / float / decimal | `Double` | 骨架暂未用到 |
| varchar / char / text 系 | `String` | |
| datetime / timestamp / date / time | `String` | 骨架口径：时间一律字符串（create_time 同物） |
| 其它/未知 | `String` | 兜底，不猜 |

可空列 → `Option[T]`；`is_pk` → 主键位；`extra` 含 `auto_increment` → 提示"应用侧生成 id"（本框架
雪花自填，auto_increment 表通常不该出现在生成范围）。

## 3. 跨库实现要点（"如何根据不同数据库的元数据"）

| 库 | 表清单 | 列清单 | 注释 | 现状 |
|---|---|---|---|---|
| MySQL | `information_schema.tables WHERE table_schema=DATABASE()` | `information_schema.columns ORDER BY ordinal_position`（column_key=PRI、extra） | table_comment / column_comment 原生 | ✅ `metadata-mysql` 已落 |
| PostgreSQL | `information_schema.tables WHERE table_schema=current_schema()` | `information_schema.columns`（is_nullable 同款） | 表/列注释在 `pg_description`（`obj_description(oid)` JOIN `pg_class`/`pg_attribute`）——实现方要自己 join 翻译进 TableMeta/ColumnMeta | 等驱动（moonstack/moonpostgres）成熟再补 |
| SQLite | `PRAGMA table_list`（或 sqlite_master） | `PRAGMA table_info(t)`（pk 列序号、notnull） | **无注释机制**——comment 恒空串；生成时用表/列名兜底 | 等驱动（moonstack/moonsqlite）成熟再补 |

设计约束（为什么是端口+方言实现，不是公共 SQL）：三库的注释取法/类型叫法/序号语义都不同，
公共抽象只能落在"形状"上。每个库一个实现包（`metadata-mysql` / `metadata-postgres` /
`metadata-sqlite`），消费方只 import `metadata` 端口——换库不动 gen/dev_schema。
连接助手与 dao-db 各持一份（模板自包含，共享需求成立再抽公共件）。

## 4. 两条消费路

1. **gen 代码生成器（已落，`cmd/gen`）**：读 `list_columns(表)` → 按 §2 映射产出六件套源码。

   ```bash
   export MLDONG_DB_* && moon run --target wasm cmd/gen/main -- <表名>... [--out=<目录>]
   ```

   - 产物 = 手写代码进仓（文件头〔cmd/gen 生成，可手改〕），非编译期挂钩子（codegen/dev_build
     路线已被 owner 否决）；`gen-out/` 不入仓；
   - 生成面 = 标准 CRUD 五端点 + 权限码片段 + 唯一编码校验一行调（`check_unique`，BaseDao
     通用件，boot2 checkUnique 同位）/ 批量查 `find_by_ids`；**权限码前缀取表名首段
     （sys_dept → sys:dept），路由前缀 = 表名首下划线换 /（/sys/dept）**——两者形状相近
     别混用（已踩）；
   - **同包多实体防撞名**：生成物 dto 顶层标识符带表内小写前缀（post_parse_save 等）——
     不加前缀会静默命中同包其它实体的同名符号（编译不报错、运行时校验面张冠李戴，已踩）；
   - **二次开发 = 直接改生成物**（boot2/各栈同做法，一处一文件不另立）：生成器**默认跳过
     已存在文件**防覆盖手改，`--force` 才整体重生成（先 diff 自己的手改）；树表等特性
     （dept 的树端点/list_all/树装配）就长在 dept_controller/dept_service/dept_mysql 各自
     文件内并以"二次开发"注释标注；dept 树语义 = parent_id 内存建树（root=0，boot2 同），
     pids 列留档不维护；
   - **跨模块件**：ConfigHolder 是 core 框架件（`core/config_holder.mbt`）——main 装配处建
     一个实例传各模块，sys 持 sys_config 表负责灌入/写路刷新，dev/biz 只读注入；
   - 接入三步见 [adding-module.md](adding-module.md)。
2. **dev_schema 导入**（boot2 同位，未落）：
   `/dev/schema/dbTable`（表清单）→ `/dev/schema/importTable`（落 dev_schema 台账表）→
   台账上改显示名/列表字段/搜索字段 → 生成器从台账读。台账六件套 + disabled 标记
   （boot2 dbTable 返回项里的 `disabled`=已导入）是下一块，端点已按 boot2 语义预留双码 OR
   （`dev:schema:dbTable` OR `dev:schema:importTable`）。

## 5. 已验证（10-04 冒烟）

- `/dev/schema/dbTable {keywords:"sys_user"}` → 2 行（sys_user/sys_user_role，带注释）；
- `/dev/schema/column/list {tableName:"sys_user"}` → 21 列；id→Int64+isPk、user_name→String+varchar(32)；
- 守卫在位：未登录 401；空 tableName 99990001；不存在表 → 空数组（不报错，导入侧自行提示）。
