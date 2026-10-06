// 应用器单测（零 DB）：framework_group 装载契约 / 文件名解析 / 归一化 / 指纹。
// DB 行为（应用/记账/幂等/篡改拒绝/重放）走真库独立收口与 e2e。
// 注：_test.mbt 里引用本包符号须用 @moon-plugin-host. 限定。

///|
async test "framework_group：装载/排序/trim 归一/非 .sql 忽略" {
  let dir = @fs.tmpdir(prefix="mplugin_ok")
  defer @fs.rmdir(dir, recursive=true)
  @fs.write_file("\{dir}/0002_second.sql", "ALTER TABLE `p_x` ADD COLUMN `b` int NULL\n")
  @fs.write_file(
    "\{dir}/0001_first.sql",
    "   CREATE TABLE `p_x` (`id` bigint NOT NULL, PRIMARY KEY (`id`))  \n",
  )
  @fs.write_file("\{dir}/README.md", "说明文件不参与")
  let g = @moon-plugin-host.framework_group(dir)
  assert_eq(g.name, "__framework__")
  assert_eq(g.plugin_version, "framework")
  assert_eq(g.tables.length(), 0)
  assert_eq(g.migrations.length(), 2)
  assert_eq(g.migrations[0].version, 1)
  assert_eq(g.migrations[1].version, 2)
  // trim 归一：首尾空白不进 ddl
  assert_true(g.migrations[0].ddl.contains("PRIMARY KEY (`id`))"))
  assert_true(!g.migrations[0].ddl.contains("   CREATE"))
  assert_true(!g.migrations[1].ddl.contains("\n"))
}

///|
async test "framework_group：空目录 = 空组（仓库初态）" {
  let dir = @fs.tmpdir(prefix="mplugin_empty")
  defer @fs.rmdir(dir, recursive=true)
  let g = @moon-plugin-host.framework_group(dir)
  assert_eq(g.migrations.length(), 0)
}

///|
async test "framework_group：版本缺口拒绝" {
  let dir = @fs.tmpdir(prefix="mplugin_gap")
  defer @fs.rmdir(dir, recursive=true)
  @fs.write_file("\{dir}/0001_a.sql", "SELECT 1")
  @fs.write_file("\{dir}/0003_c.sql", "SELECT 3")
  let mut err = ""
  let g : @moon-plugin-host.MigrationGroup = @moon-plugin-host.framework_group(dir) catch {
    e => {
      err = @core.MldongError::message(e)
      { name: "", plugin_version: "", spec_version: 0, tables: [], migrations: [] }
    }
  }
  assert_true(err.contains("缺口"))
  assert_eq(g.name, "")
}

///|
async test "framework_group：版本重号拒绝" {
  let dir = @fs.tmpdir(prefix="mplugin_dup")
  defer @fs.rmdir(dir, recursive=true)
  @fs.write_file("\{dir}/0001_a.sql", "SELECT 1")
  @fs.write_file("\{dir}/0001_b.sql", "SELECT 1 again")
  let mut err = ""
  let g : @moon-plugin-host.MigrationGroup = @moon-plugin-host.framework_group(dir) catch {
    e => {
      err = @core.MldongError::message(e)
      { name: "", plugin_version: "", spec_version: 0, tables: [], migrations: [] }
    }
  }
  assert_true(err.contains("重号"))
  assert_eq(g.name, "")
}

///|
test "framework_group：文件名形状不合法拒绝（无数字段 / 无下划线）" {
  let mut err1 = ""
  let v1 : Int = @moon-plugin-host.parse_migration_version("abc_x.sql") catch {
    e => {
      err1 = @core.MldongError::message(e)
      0
    }
  }
  assert_true(err1.contains("文件名不合法"))
  assert_eq(v1, 0)
  let mut err2 = ""
  let v2 : Int = @moon-plugin-host.parse_migration_version("0007.sql") catch {
    e => {
      err2 = @core.MldongError::message(e)
      0
    }
  }
  assert_true(err2.contains("文件名不合法"))
  assert_eq(v2, 0)
}

///|
test "framework_group：版本号解析（前导数字段）" {
  assert_eq(@moon-plugin-host.parse_migration_version("0007_wf_x.sql"), 7)
  assert_eq(@moon-plugin-host.parse_migration_version("1_init.sql"), 1)
  assert_eq(
    @moon-plugin-host.parse_migration_version("0042_add_two_columns.sql"),
    42,
  )
}

///|
test "ddl_md5：指纹对归一文本稳定（标准向量 + 同文本同指纹）" {
  // md5("") 标准向量
  assert_eq(@moon-plugin-host.ddl_md5(""), "d41d8cd98f00b204e9800998ecf8427e")
  assert_eq(
    @moon-plugin-host.ddl_md5("SELECT 1"),
    @moon-plugin-host.ddl_md5("SELECT 1"),
  )
  assert_true(
    @moon-plugin-host.ddl_md5("SELECT 1") != @moon-plugin-host.ddl_md5("SELECT 2"),
  )
}
