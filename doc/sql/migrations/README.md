# __framework__ 基线增量目录（plugin-host 装载器装载）

- 一个文件 = 一条语句（驱动硬约束：多语句被拒且零半执行）。
- 文件名 `NNNN_说明.sql`，version = 前导数字段（`0007_wf_x.sql` → 7）；version 从 1 起连续。
- 目录只增不删不改：改已应用的文本必撞台账 md5（拒绝启动）；合并（把增量固化进
  `../mysql-schema-all.sql`）时不删文件，只抬 `plugin-host/framework.mbt` 的 `BASELINE_NO`。
- 指纹 = trim 后语句文本的 md5（人补换行不误报篡改）。
