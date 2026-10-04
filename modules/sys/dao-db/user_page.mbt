// sys_user 关联分页 —— 对齐 boot2 UserMapper.selectCustom：
// 主表别名 t + left join sys_dept d / sys_post p，动态条件 service 拼带前缀的 Wrapper；
// 单表通用操作仍走 BaseDao，本文件只装 join 版分页（业务特有形状）

///|
const USER_PAGE_COLS : String = "t.id, t.user_name, t.real_name, t.nick_name, t.mobile_phone, t.tel, t.email, t.sex, t.admin_type, t.is_locked, t.dept_id, t.remark, t.create_time, t.update_time, t.is_deleted, d.name as dept_name, d.code as dept_code, p.name as post_name, p.code as post_code"

///|
const USER_PAGE_FROM : String = "sys_user t"

///|
fn user_page_joins() -> Array[@core.Join] {
  [
    { kind: Left, table: "sys_dept d", on: "t.dept_id = d.id" },
    { kind: Left, table: "sys_post p", on: "t.post_id = p.id" },
  ]
}

///|
/// 关联行 → UserPageRow（user 部分复用 row_user：by_name 不受表前缀影响）
fn row_page(r : @moondb.Row) -> @entity.UserPageRow {
  {
    user: row_user(r),
    dept_name: row_opt_text(r, "dept_name"),
    dept_code: row_opt_text(r, "dept_code"),
    post_name: row_opt_text(r, "post_name"),
    post_code: row_opt_text(r, "post_code"),
  }
}

///|
pub impl @dao.UserDao for UserDbDao with fn page(self, w, page_num, page_size) {
  let joins = user_page_joins()
  let conn = open_conn(self.base.config)
  // 总数（join 保留：动态条件可能引用 d./p. 列）
  let (where_sql, params) = w.build()
  let count_rows = q(
    conn,
    "SELECT COUNT(*) AS cnt FROM \{USER_PAGE_FROM} LEFT JOIN sys_dept d ON t.dept_id = d.id LEFT JOIN sys_post p ON t.post_id = p.id \{where_sql}",
    to_db_values(params),
  )
  let total = row_i64(count_rows[0], "cnt").to_int()
  let rows : Array[@entity.UserPageRow] = []
  if total > 0 {
    // 数据页：builder 拼（joins/orders 全走参数）；排序对齐 boot2：d.sort → p.sort → t.user_name 升序
    let (sql, db_params) = @core.build_select(
      USER_PAGE_FROM,
      [USER_PAGE_COLS],
      w,
      joins=joins,
      orders=[("d.sort", false), ("p.sort", false), ("t.user_name", false)],
      limit=page_size,
      offset=(page_num - 1) * page_size,
    )
    for r in q(conn, sql, to_db_values(db_params)) {
      rows.push(row_page(r))
    }
  }
  conn.close()
  (total, rows)
}
