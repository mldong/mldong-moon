// SysQueryApi 实现 —— 插件可见的 sys 查询面（契约在 plugin-api；依赖倒置：框架层实现
// 接口，cmd/main 注册插件时注入 PluginContext；插件不依赖本模块）。
// v1 方法集 = jeeflow 引擎供数所需（boot4 JeeflowUserProvider/OrgUserProvider/
// UserSearchProvider 的数据流反推）：用户详情(join dept/post 名)/用户分页(keywords)/
// 全量部门(领导字段)/角色编码→用户对。只读；每方法独立连接（BaseDao 同款模式）；
// 逻辑删范围过滤。

///|
pub struct SysQueryApiImpl {
  config : @core.MysqlConfig
}

///|
pub extend SysQueryApiImpl with @api.SysQueryApi::{user_by_id, user_page, dept_list, role_user_pairs}

///|
pub fn SysQueryApiImpl::make(config : @core.MysqlConfig) -> SysQueryApiImpl {
  { config, }
}

///|
const SYS_QUERY_USER_COLS : String = "t.id, t.user_name, t.real_name, t.dept_id, d.name AS dept_name, t.post_id, p.name AS post_name"

///|
const SYS_QUERY_USER_FROM_JOINS : String = "sys_user t LEFT JOIN sys_dept d ON t.dept_id = d.id LEFT JOIN sys_post p ON t.post_id = p.id"

///|
fn sys_query_user_joins() -> Array[@core.Join] {
  [
    { kind: Left, table: "sys_dept d", on: "t.dept_id = d.id" },
    { kind: Left, table: "sys_post p", on: "t.post_id = p.id" },
  ]
}

///|
fn sys_query_user_row(r : @moondb.Row) -> @api.SysUserRow {
  {
    id: row_i64(r, "id"),
    user_name: row_text(r, "user_name", ""),
    real_name: row_text(r, "real_name", ""),
    dept_id: row_opt_i64(r, "dept_id"),
    dept_name: row_opt_text(r, "dept_name"),
    post_id: row_opt_i64(r, "post_id"),
    post_name: row_opt_text(r, "post_name"),
  }
}

///|
/// 逗号串 → 去空白去空的 id 串数组（sys_dept.leader_ids 形状）
fn split_ids(s : String) -> Array[String] {
  let ids : Array[String] = []
  let sb = StringBuilder()
  let mut emitting = false
  let n = s.length()
  for i in 0..=n {
    let mut c = ','
    if i < n {
      match s.get_char(i) {
        Some(ch) => c = ch
        None => c = ','
      }
    }
    if c != ',' {
      sb.write_char(c)
      emitting = true
    } else if emitting {
      let piece = sb.to_string().trim().to_owned()
      if !piece.is_empty() {
        ids.push(piece)
      }
      sb.reset()
      emitting = false
    }
  }
  ids
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn user_by_id(
  self,
  id : Int64,
) -> @api.SysUserRow? raise @core.MldongError {
  let conn = open_conn(self.config)
  defer close_conn(conn)
  let rows = q(
    conn,
    "SELECT \{SYS_QUERY_USER_COLS} FROM \{SYS_QUERY_USER_FROM_JOINS} WHERE t.id = ? AND t.is_deleted = 0",
    to_db_values([@core.L(id)]),
  )
  if rows.is_empty() {
    None
  } else {
    Some(sys_query_user_row(rows[0]))
  }
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn user_page(
  self,
  page : Int,
  size : Int,
  keyword : String,
) -> @api.SysUserPage raise @core.MldongError {
  let conn = open_conn(self.config)
  defer close_conn(conn)
  let w = @core.where_().eq("t.is_deleted", @core.I(0))
  if !keyword.is_empty() {
    let like = "%\{keyword}%"
    let _ = w.raw("(t.user_name LIKE ? OR t.real_name LIKE ?)", [@core.S(like), @core.S(like)])
  }
  let (where_sql, w_params) = w.build()
  let count_rows = q(
    conn,
    "SELECT COUNT(*) AS cnt FROM \{SYS_QUERY_USER_FROM_JOINS} \{where_sql}",
    to_db_values(w_params),
  )
  let total = row_i64(count_rows[0], "cnt").to_int()
  let rows : Array[@api.SysUserRow] = []
  if total > 0 {
    let offset = (page - 1) * size
    let (sql, params) = @core.build_select(
      "sys_user t",
      [SYS_QUERY_USER_COLS],
      w,
      joins=sys_query_user_joins(),
      orders=[("t.id", true)],
      limit=size,
      offset=offset,
    )
    let all_params = to_db_values(params)
    for v in to_db_values([@core.I(size), @core.I(offset)]) {
      all_params.push(v)
    }
    let page_rows = q(conn, sql, all_params)
    for r in page_rows {
      rows.push(sys_query_user_row(r))
    }
  }
  { rows, record_count: total }
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn dept_list(
  self,
) -> Array[@api.SysDeptRow] raise @core.MldongError {
  let conn = open_conn(self.config)
  defer close_conn(conn)
  let rows = q(
    conn,
    "SELECT id, name, leader_ids, main_leader_id FROM sys_dept WHERE is_deleted = 0 ORDER BY id",
    [],
  )
  let out : Array[@api.SysDeptRow] = []
  for r in rows {
    out.push({
      id: row_i64(r, "id"),
      name: row_text(r, "name", ""),
      leader_ids: split_ids(row_text(r, "leader_ids", "")),
      main_leader_id: row_opt_i64(r, "main_leader_id"),
    })
  }
  out
}

///|
pub impl @api.SysQueryApi for SysQueryApiImpl with fn role_user_pairs(
  self,
) -> Array[@api.SysRoleUser] raise @core.MldongError {
  let conn = open_conn(self.config)
  defer close_conn(conn)
  let rows = q(
    conn,
    "SELECT r.code AS role_code, ur.user_id FROM sys_user_role ur JOIN sys_role r ON ur.role_id = r.id JOIN sys_user u ON u.id = ur.user_id WHERE r.is_deleted = 0 AND u.is_deleted = 0 ORDER BY r.code, ur.user_id",
    [],
  )
  let out : Array[@api.SysRoleUser] = []
  for r in rows {
    out.push({ role_code: row_text(r, "role_code", ""), user_id: row_i64(r, "user_id").to_string() })
  }
  out
}
