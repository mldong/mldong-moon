// sys_dept MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct DeptDbDao {
  base : BaseDao[@entity.Dept]
}

///|
pub fn DeptDbDao::make(config : @core.MysqlConfig) -> DeptDbDao {
  { base: { config, table: dept_table } }
}

///|
pub impl @dao.DeptDao for DeptDbDao with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.DeptDao for DeptDbDao with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.DeptDao for DeptDbDao with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.DeptDao for DeptDbDao with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.DeptDao for DeptDbDao with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.DeptDao for DeptDbDao with fn check_unique(
  self,
  code,
  exclude_id,
  msg,
) {
  self.base.check_unique("code", S(code), exclude_id, msg)
}

///|
pub impl @dao.DeptDao for DeptDbDao with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

pub extend DeptDbDao with @dao.DeptDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
}

///|
/// 全量部门（树装配取数；sort 升序、同序按 id）——二次开发（树表），重生成 --force 时需并回
pub impl @dao.DeptDao for DeptDbDao with fn list_all(self) {
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
