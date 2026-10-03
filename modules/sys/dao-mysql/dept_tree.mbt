// sys_dept 树扩展 —— dept 是树型表（parent_id 内存建树，root=0；boot2 同语义：
// pids 列留档不维护）。本文件是生成器之外的手写扩展面，重生成不覆盖。

///|
/// 全量部门（sort 升序、同序按 id；树装配前的一次性取数）
pub async fn DeptMysqlDao::list_all(self : DeptMysqlDao) -> Array[@entity.Dept] raise @core.MldongError {
  let (sql, params) = @core.build_select(
    "sys_dept",
    self.base.table.cols,
    self.base.base_where(),
    orders=[("sort", false), ("id", false)],
  )
  let out : Array[@entity.Dept] = []
  for r in self.base.query(sql, params) {
    out.push((self.base.table.from_row)(r))
  }
  out
}
