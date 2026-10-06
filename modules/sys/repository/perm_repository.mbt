// RBAC MySQL 仓储 —— 权限链 join 查询 + 中间表授权写路（删旧插新，局部事务：
// BEGIN → DELETE → 批量 INSERT → COMMIT，errdefer ROLLBACK——请求作用域事务模板（后续轮）落地前的
// 最小原地实现，模板就位后收敛过去）

///|
pub(all) struct RbacRepository {
  config : @core.MysqlConfig
}

///|
pub fn RbacRepository::make(config : @core.MysqlConfig) -> RbacRepository {
  { config: config }
}

///|
pub impl @dao.RbacDao for RbacRepository with fn find_user_auth_by_name(self, user_name) {
  let conn = open_conn(self.config)
  let rows = q(
    conn,
    "SELECT id, user_name, admin_type, is_locked, password, salt FROM sys_user WHERE user_name = ? AND is_deleted = 0 LIMIT 1",
    [@moondb.Text(user_name)],
  )
  conn.close()
  if rows.is_empty() {
    None
  } else {
    Some(user_auth_of(rows[0]))
  }
}

///|
pub impl @dao.RbacDao for RbacRepository with fn find_user_auth_by_id(self, id) {
  let conn = open_conn(self.config)
  let rows = q(
    conn,
    "SELECT id, user_name, admin_type, is_locked, password, salt FROM sys_user WHERE id = ? AND is_deleted = 0 LIMIT 1",
    [@moondb.Int64(id)],
  )
  conn.close()
  if rows.is_empty() {
    None
  } else {
    Some(user_auth_of(rows[0]))
  }
}

///|
pub impl @dao.RbacDao for RbacRepository with fn find_role_codes(self, user_id, app_code) {
  let conn = open_conn(self.config)
  let rows = q(
    conn,
    "SELECT r.code FROM sys_role r JOIN sys_user_role ur ON ur.role_id = r.id WHERE ur.user_id = ? AND r.app_code = ? AND r.is_deleted = 0",
    [@moondb.Int64(user_id), @moondb.Text(app_code)],
  )
  conn.close()
  let out : Array[String] = []
  for r in rows {
    out.push(row_text(r, "code", ""))
  }
  out
}

///|
pub impl @dao.RbacDao for RbacRepository with fn find_perms_by_user(self, user_id, app_code) {
  let conn = open_conn(self.config)
  let rows = q(
    conn,
    "SELECT DISTINCT m.code FROM sys_menu m JOIN sys_role_menu rm ON rm.menu_id = m.id JOIN sys_user_role ur ON ur.role_id = rm.role_id JOIN sys_role r ON r.id = ur.role_id WHERE ur.user_id = ? AND r.app_code = ? AND m.app_code = ? AND m.is_deleted = 0",
    [@moondb.Int64(user_id), @moondb.Text(app_code), @moondb.Text(app_code)],
  )
  conn.close()
  let out : Array[String] = []
  for r in rows {
    let code = row_text(r, "code", "")
    if !code.is_empty() {
      out.push(code)
    }
  }
  out
}

///|
/// 全量替换：DELETE 旧关系 → 批量 INSERT 新关系（局部事务保证不留半态）
pub impl @dao.RbacDao for RbacRepository with fn grant_roles(self, user_id, role_ids) {
  let conn = open_conn(self.config)
  // 局部事务（模板就位前先原地实现）
  try {
    tx_begin(conn)
  } catch {
    e => {
      close_conn(conn)
      raise @core.MldongError::Internal("grant_roles begin: " + e.message())
    }
  }
  errdefer {
    try {
      tx_rollback(conn)
    } catch {
      _ => ()
    }
    close_conn(conn)
  }
  let _ = x(conn, "DELETE FROM sys_user_role WHERE user_id = ?", [@moondb.Int64(user_id)])
  for role_id in role_ids {
    let _ = x(
      conn,
      "INSERT INTO sys_user_role (id, user_id, role_id) VALUES (?, ?, ?)",
      [@moondb.Int64(@core.next_id()), @moondb.Int64(user_id), @moondb.Int64(role_id)],
    )
  }
  try {
    tx_commit(conn)
  } catch {
    e => raise @core.MldongError::Internal("grant_roles commit: " + e.message())
  }
  conn.close()
}

///|
pub impl @dao.RbacDao for RbacRepository with fn grant_menus(self, role_id, menu_ids) {
  let conn = open_conn(self.config)
  try {
    tx_begin(conn)
  } catch {
    e => {
      close_conn(conn)
      raise @core.MldongError::Internal("grant_menus begin: " + e.message())
    }
  }
  errdefer {
    try {
      tx_rollback(conn)
    } catch {
      _ => ()
    }
    close_conn(conn)
  }
  let _ = x(conn, "DELETE FROM sys_role_menu WHERE role_id = ?", [@moondb.Int64(role_id)])
  for menu_id in menu_ids {
    let _ = x(
      conn,
      "INSERT INTO sys_role_menu (id, role_id, menu_id) VALUES (?, ?, ?)",
      [@moondb.Int64(@core.next_id()), @moondb.Int64(role_id), @moondb.Int64(menu_id)],
    )
  }
  try {
    tx_commit(conn)
  } catch {
    e => raise @core.MldongError::Internal("grant_menus commit: " + e.message())
  }
  conn.close()
}

///|

///|
fn user_auth_of(r : @moondb.Row) -> @entity.UserAuth {
  {
    id: row_i64(r, "id"),
    user_name: row_text(r, "user_name", ""),
    admin_type: row_opt_int(r, "admin_type"),
    is_locked: row_opt_int(r, "is_locked"),
    password: row_opt_text(r, "password"),
    salt: row_opt_text(r, "salt"),
  }
}

///|

///|
///|
pub impl @dao.RbacDao for RbacRepository with fn find_menu_ids_by_user(self, user_id, app_code) {
  let conn = open_conn(self.config)
  let rows = q(
    conn,
    "SELECT DISTINCT m.id FROM sys_menu m JOIN sys_role_menu rm ON rm.menu_id = m.id JOIN sys_user_role ur ON ur.role_id = rm.role_id JOIN sys_role r ON r.id = ur.role_id WHERE ur.user_id = ? AND r.app_code = ? AND m.app_code = ? AND m.is_deleted = 0",
    [@moondb.Int64(user_id), @moondb.Text(app_code), @moondb.Text(app_code)],
  )
  conn.close()
  let out : Array[Int64] = []
  for r in rows {
    let id = row_i64(r, "id")
    if id != 0L {
      out.push(id)
    }
  }
  out
}

///|
pub impl @dao.RbacDao for RbacRepository with fn remove_role_menus_by_menu_ids(self, menu_ids) {
  if menu_ids.is_empty() {
    return
  }
  let conn = open_conn(self.config)
  let marks : Array[String] = []
  let params : Array[@moondb.Value] = []
  for id in menu_ids {
    marks.push("?")
    params.push(@moondb.Int64(id))
  }
  let _ = x(
    conn,
    "DELETE FROM sys_role_menu WHERE menu_id IN (\{marks.join(",")})",
    params,
  )
  conn.close()
}

pub extend RbacRepository with @dao.RbacDao::{
  find_user_auth_by_name,
  find_user_auth_by_id,
  find_role_codes,
  find_perms_by_user,
  grant_roles,
  grant_menus,
  find_menu_ids_by_user,
  remove_role_menus_by_menu_ids,
  remove_user_role_pairs,
  grant_data_scope,
  find_menu_ids_by_role,
  page_users_by_role,
  grant_user_role_pairs
}

// ── RBAC 授权面（boot2 RbacController/RoleController#grantDataScope 同位）──

///|
pub impl @dao.RbacDao for RbacRepository with fn find_menu_ids_by_role(self, role_id) {
  let conn = open_conn(self.config)
  let rows = q(
    conn,
    "SELECT menu_id FROM sys_role_menu WHERE role_id = ?",
    [@moondb.Int64(role_id)],
  )
  conn.close()
  let out : Array[Int64] = []
  for r in rows {
    out.push(row_i64(r, "menu_id"))
  }
  out
}

///|
pub impl @dao.RbacDao for RbacRepository with fn grant_user_role_pairs(self, pairs) {
  let conn = open_conn(self.config)
  errdefer close_conn(conn)
  for pair in pairs {
    let (user_id, role_id) = pair
    // 增量插（IGNORE 防重复对；uk_user_role 唯一键兜底）
    let _ = x(
      conn,
      "INSERT IGNORE INTO sys_user_role (id, user_id, role_id) VALUES (?, ?, ?)",
      [@moondb.Int64(@core.next_id()), @moondb.Int64(user_id), @moondb.Int64(role_id)],
    )
  }
  conn.close()
}

///|
pub impl @dao.RbacDao for RbacRepository with fn remove_user_role_pairs(self, pairs) {
  let conn = open_conn(self.config)
  errdefer close_conn(conn)
  for pair in pairs {
    let (user_id, role_id) = pair
    let _ = x(
      conn,
      "DELETE FROM sys_user_role WHERE user_id = ? AND role_id = ?",
      [@moondb.Int64(user_id), @moondb.Int64(role_id)],
    )
  }
  conn.close()
}

///|
pub impl @dao.RbacDao for RbacRepository with fn page_users_by_role(
  self,
  role_id,
  in_role,
  w,
  page_num,
  page_size,
) {
  let conn = open_conn(self.config)
  errdefer close_conn(conn)
  let join = if in_role {
    "JOIN sys_user_role ur ON ur.user_id = u.id AND ur.role_id = ?"
  } else {
    "LEFT JOIN sys_user_role ur ON ur.user_id = u.id AND ur.role_id = ?"
  }
  let not_exists = if in_role { "" } else { " AND ur.id IS NULL" }
  let (wsql_raw, wparams) = w.build()
  // Wrapper::build 返回带 "WHERE " 前缀——这里主 WHERE 已自拼，剥前缀留裸条件
  let wsql = if wsql_raw.has_prefix("WHERE ") { wsql_raw["WHERE ".length():].to_owned() } else { wsql_raw }
  let where_sql = if wsql.is_empty() {
    " WHERE u.is_deleted = 0\{not_exists}"
  } else {
    " WHERE u.is_deleted = 0 AND \{wsql}\{not_exists}"
  }
  let params : Array[@core.SqlValue] = [@core.L(role_id)]
  for p in wparams {
    params.push(p)
  }
  let count_rows = q(
    conn,
    "SELECT COUNT(*) AS c FROM sys_user u \{join}\{where_sql}",
    to_db_values(params),
  )
  let total = if count_rows.is_empty() { 0 } else { row_int_d(count_rows[0], "c", 0) }
  let rows = q(
    conn,
    "SELECT u.* FROM sys_user u \{join}\{where_sql} ORDER BY u.id ASC LIMIT \{page_size} OFFSET \{(page_num - 1) * page_size}",
    to_db_values(params),
  )
  conn.close()
  let out : Array[@entity.User] = []
  for r in rows {
    out.push(row_user(r))
  }
  (total, out)
}

///|
pub impl @dao.RbacDao for RbacRepository with fn grant_data_scope(self, role_id, data_scope, dept_ids) {
  let conn = open_conn(self.config)
  errdefer {
    try {
      tx_rollback(conn)
    } catch {
      _ => ()
    }
    close_conn(conn)
  }
  tx_begin(conn)
  match data_scope {
    Some(ds) => {
      let _ = x(
        conn,
        "UPDATE sys_role SET data_scope = ?, update_time = ? WHERE id = ?",
        [@moondb.Int(ds), @moondb.Text(@core.now_str()), @moondb.Int64(role_id)],
      )
    }
    None => ()
  }
  // 部门明细全量替换（自定义范围(5)才有非空清单；boot2 同语义）
  let _ = x(conn, "DELETE FROM sys_role_dept WHERE role_id = ?", [@moondb.Int64(role_id)])
  for dept_id in dept_ids {
    let _ = x(
      conn,
      "INSERT INTO sys_role_dept (id, role_id, dept_id) VALUES (?, ?, ?)",
      [@moondb.Int64(@core.next_id()), @moondb.Int64(role_id), @moondb.Int64(dept_id)],
    )
  }
  tx_commit(conn)
  conn.close()
}
