// gen 代码生成器入口 —— 读活库元数据（MetadataDao）产出六件套源码
//
// 用法：
//   export MLDONG_DB_*（同主程序）&& moon run --target wasm cmd/gen -- <表名>...
//   可选 --out=<目录>（默认 gen-out，目录按六件套包名铺开，拷进 modules/<模块>/ 即接入）
//
// 设计：产物即手写代码（进仓，非编译期挂钩子）；生成文件头带〔cmd/gen 生成〕标记。
// 权限码前缀 = 表名去首个下划线（sys_dept → sys:dept）。

///|
async fn main raise {
  let args = @env.args()
  let mut out_root = "gen-out"
  let tables : Array[String] = []
  for a in args {
    // moonrun 会把 wasm 自身路径塞进 argv，滤掉
    if a.has_suffix(".wasm") || a.contains("_build") {
      continue
    }
    if a.has_prefix("--out=") {
      out_root = a.substring(start=6).to_string()
    } else if a != "--" {
      tables.push(a)
    }
  }
  if tables.is_empty() {
    println("用法: moon run --target wasm cmd/gen -- <表名>... [--out=<目录>]")
    println("示例: moon run --target wasm cmd/gen -- sys_dept sys_post --out=gen-out")
    return
  }
  let config = @core.MysqlConfig::from_env()
  gen_all(@metamysql.MetadataMysqlDao::make(config), tables, out_root)
  println("完成。")
}

///|
async fn[M : @meta.MetadataDao] gen_all(dao : M, tables : Array[String], out_root : String) -> Unit raise {
  for table in tables {
    println("== 生成 " + table)
    let cols_meta = dao.list_columns(table)
    if cols_meta.is_empty() {
      println("   !! 表不存在或无列（检查 MLDONG_DB_NAME）: " + table)
      continue
    }
    let class_name = table_to_class(table)
    let lc = class_name.to_lower()
    // 权限码前缀：sys_dept → sys:dept
    let perm = match table.find("_") {
      Some(i) =>
        table.substring(start=0, end=i) + ":" + table.substring(start=i + 1)
      None => table
    }
    let has_code = cols_meta.filter(fn(c) { c.name == "code" }).length() > 0
    let plan : TablePlan = {
      table,
      class_name,
      perm,
      lc,
      cols: cols_meta.map(classify),
      has_code,
    }
    for files in render_all(plan) {
      let rel = files.0
      let path = out_root + "/" + rel
      let dir = match rel.find("/") {
        Some(i) => out_root + "/" + rel.substring(start=0, end=i)
        None => out_root
      }
      @fs.mkdir(dir, recursive=true, allow_exist=true)
      @fs.write_file(path, files.1, create_mode=@fs.CreateOrTruncate)
      println("   + " + path)
    }
    println("   接入三步：① 文件拷进 modules/<模块>/ 对应包目录")
    println("   ② module.mbt 加 dao/svc 构造 + register_" + lc)
    println("   ③ 模块 policy() 并进 " + lc + "_policy()（见 doc/adding-module.md）")
  }
}
