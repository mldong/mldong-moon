// RBAC MySQL 仓储 —— 权限链 join 查询 + 中间表授权写路（删旧插新，局部事务：
// BEGIN → DELETE → 批量 INSERT → COMMIT，errdefer ROLLBACK——事务模板（§6.4.1）落地前的
// 最小原地实现，模板就位后收敛过去）

///|
pub(all) struct RbacDaoDb {
  config : @core.MysqlConfig
}

///|
pub fn RbacDaoDb::make(config : @core.MysqlConfig) -> RbacDaoDb {
  { config }
}

///|
pub impl @dao.RbacDao for RbacDaoDb with fn find_user_auth_by_name(self, user_name) {
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
pub impl @dao.RbacDao for RbacDaoDb with fn find_user_auth_by_id(self, id) {
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
pub impl @dao.RbacDao for RbacDaoDb with fn find_role_codes(self, user_id, app_code) {
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
pub impl @dao.RbacDao for RbacDaoDb with fn find_perms_by_user(self, user_id, app_code) {
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
pub impl @dao.RbacDao for RbacDaoDb with fn grant_roles(self, user_id, role_ids) {
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
pub impl @dao.RbacDao for RbacDaoDb with fn grant_menus(self, role_id, menu_ids) {
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
pub extend RbacDaoDb with @dao.RbacDao::{
  grant_roles,
  grant_menus,
  find_perms_by_user,
  find_role_codes,
  find_user_auth_by_name,
  find_user_auth_by_id,
}

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
