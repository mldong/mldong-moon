// sys_user MySQL 仓储 —— 手写 SQL（MyBatis 式），行映射按列名取；moondb+moonmysql 只进本包

///|
pub(all) struct UserMysqlDao {
  config : MysqlConfig
}

///|
const USER_COLS : String = "id, user_name, real_name, nick_name, mobile_phone, tel, email, sex, is_locked, dept_id, remark, create_time, update_time, is_deleted"

///|
pub impl @dao.UserDao for UserMysqlDao with fn insert(self, u) {
  let conn = self.config.open_conn()
  let r = x(
    conn,
    "INSERT INTO sys_user (id, user_name, real_name, nick_name, mobile_phone, tel, email, sex, is_locked, dept_id, remark, create_time, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)",
    [
      @moondb.Int64(u.id),
      @moondb.Text(u.user_name),
      @moondb.Text(u.real_name),
      opt_text(u.nick_name),
      opt_text(u.mobile_phone),
      opt_text(u.tel),
      opt_text(u.email),
      opt_int(u.sex),
      opt_int(u.is_locked),
      opt_i64(u.dept_id),
      opt_text(u.remark),
      @moondb.Text(@core.now_str()),
    ],
  )
  conn.close()
  let _ = r
  u.id
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn update(self, u) {
  let conn = self.config.open_conn()
  let r = x(
    conn,
    "UPDATE sys_user SET user_name=?, real_name=?, nick_name=?, mobile_phone=?, tel=?, email=?, sex=?, dept_id=?, remark=?, update_time=? WHERE id=? AND is_deleted=0",
    [
      @moondb.Text(u.user_name),
      @moondb.Text(u.real_name),
      opt_text(u.nick_name),
      opt_text(u.mobile_phone),
      opt_text(u.tel),
      opt_text(u.email),
      opt_int(u.sex),
      opt_i64(u.dept_id),
      opt_text(u.remark),
      @moondb.Text(@core.now_str()),
      @moondb.Int64(u.id),
    ],
  )
  conn.close()
  let _ = r
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn remove_by_ids(self, ids) {
  if ids.is_empty() {
    return
  }
  let marks = StringBuilder()
  let params : Array[@moondb.Value] = []
  for i, id in ids {
    if i > 0 {
      marks.write_string(",")
    }
    marks.write_string("?")
    params.push(@moondb.Int64(id))
  }
  params.insert(0, @moondb.Text(@core.now_str()))
  let conn = self.config.open_conn()
  let r = x(
    conn,
    "UPDATE sys_user SET is_deleted=1, update_time=? WHERE id IN (\{marks.to_string()})",
    params,
  )
  conn.close()
  let _ = r
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn find_by_id(self, id) {
  let conn = self.config.open_conn()
  let rows = q(
    conn,
    "SELECT \{USER_COLS} FROM sys_user WHERE id = ? AND is_deleted=0",
    [@moondb.Int64(id)],
  )
  conn.close()
  if rows.is_empty() {
    None
  } else {
    Some(row_user(rows[0]))
  }
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn find_by_user_name(self, user_name) {
  let conn = self.config.open_conn()
  let rows = q(
    conn,
    "SELECT \{USER_COLS} FROM sys_user WHERE user_name = ? AND is_deleted=0 LIMIT 1",
    [@moondb.Text(user_name)],
  )
  conn.close()
  if rows.is_empty() {
    None
  } else {
    Some(row_user(rows[0]))
  }
}

///|
pub impl @dao.UserDao for UserMysqlDao with fn page(self, req) {
  // 动态 WHERE：骨架硬编码两条 m_LIKE（m_ 通用件后续移植）
  let mut where_sql = "is_deleted=0"
  let params : Array[@moondb.Value] = []
  match req.like_user_name {
    Some(s) => {
      where_sql = where_sql + " AND user_name LIKE CONCAT('%',?,'%')"
      params.push(@moondb.Text(s))
    }
    None => ()
  }
  match req.like_real_name {
    Some(s) => {
      where_sql = where_sql + " AND real_name LIKE CONCAT('%',?,'%')"
      params.push(@moondb.Text(s))
    }
    None => ()
  }
  let conn = self.config.open_conn()
  let count_rows = q(
    conn,
    "SELECT COUNT(*) AS cnt FROM sys_user WHERE \{where_sql}",
    params,
  )
  let total = row_i64(count_rows[0], "cnt").to_int()
  let rows : Array[@entity.User] = []
  if total > 0 {
    let offset = (req.page_num - 1) * req.page_size
    params.push(@moondb.Int(req.page_size))
    params.push(@moondb.Int(offset))
    let data_rows = q(
      conn,
      "SELECT \{USER_COLS} FROM sys_user WHERE \{where_sql} ORDER BY create_time DESC, id DESC LIMIT ? OFFSET ?",
      params,
    )
    for r in data_rows {
      rows.push(row_user(r))
    }
  }
  conn.close()
  (total, rows)
}

///|
/// 行映射按列名取 —— MyBatis resultMap 的手写对应物（avatar/password/salt 等骨架不回显）
fn row_user(r : @moondb.Row) -> @entity.User {
  {
    id: row_i64(r, "id"),
    user_name: row_text(r, "user_name", ""),
    real_name: row_text(r, "real_name", ""),
    nick_name: row_opt_text(r, "nick_name"),
    avatar: None,
    password: None,
    salt: None,
    mobile_phone: row_opt_text(r, "mobile_phone"),
    tel: row_opt_text(r, "tel"),
    email: row_opt_text(r, "email"),
    admin_type: None,
    sex: row_opt_int(r, "sex"),
    is_locked: row_opt_int(r, "is_locked"),
    dept_id: row_opt_i64(r, "dept_id"),
    post_id: None,
    remark: row_opt_text(r, "remark"),
    create_time: row_opt_datetime(r, "create_time"),
    create_user: None,
    update_time: row_opt_datetime(r, "update_time"),
    update_user: None,
    is_deleted: row_opt_int(r, "is_deleted"),
  }
}

///|
pub extend UserMysqlDao with @dao.UserDao::{
  page,
  remove_by_ids,
  find_by_user_name,
  find_by_id,
  insert,
  update,
}
