// sys_message MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct MessageRepository {
  base : BaseDao[@entity.Message]
}

///|
pub fn MessageRepository::make(config : @core.MysqlConfig) -> MessageRepository {
  { base: { config, table: message_table } }
}

///|
pub impl @dao.MessageDao for MessageRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.MessageDao for MessageRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.MessageDao for MessageRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.MessageDao for MessageRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.MessageDao for MessageRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.MessageDao for MessageRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

pub extend MessageRepository with @dao.MessageDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
}

// ── 接收人隔离扩展（boot2 MessageServiceImpl 强制 receiver + appCode biz_type 前缀）──

///|
fn message_in_clause(ids : Array[Int64]) -> String {
  let marks = StringBuilder()
  for i, _ in ids {
    if i > 0 {
      marks.write_string(",")
    }
    marks.write_string("?")
  }
  marks.to_string()
}

///|
pub impl @dao.MessageDao for MessageRepository with fn count_unread(self, receiver_id, biz_pat) {
  let conn = open_conn(self.base.config)
  let rows = q(
    conn,
    "SELECT COUNT(*) AS c FROM sys_message WHERE receiver_user_id = ? AND is_read = 0 AND is_deleted = 0 AND biz_type LIKE ?",
    [@moondb.Int64(receiver_id), @moondb.Text(biz_pat)],
  )
  conn.close()
  if rows.is_empty() {
    0
  } else {
    row_int_d(rows[0], "c", 0)
  }
}

///|
pub impl @dao.MessageDao for MessageRepository with fn count_unread_group(self, receiver_id, biz_pat) {
  let conn = open_conn(self.base.config)
  let rows = q(
    conn,
    "SELECT biz_type, COUNT(*) AS c FROM sys_message WHERE receiver_user_id = ? AND is_read = 0 AND is_deleted = 0 AND biz_type LIKE ? GROUP BY biz_type ORDER BY biz_type ASC",
    [@moondb.Int64(receiver_id), @moondb.Text(biz_pat)],
  )
  conn.close()
  let out : Array[(String, Int)] = []
  for r in rows {
    out.push((row_text(r, "biz_type", ""), row_int_d(r, "c", 0)))
  }
  out
}

///|
pub impl @dao.MessageDao for MessageRepository with fn set_read(self, receiver_id, biz_pat, ids) {
  let conn = open_conn(self.base.config)
  errdefer close_conn(conn)
  let sql = if ids.is_empty() {
    "UPDATE sys_message SET is_read = 1, update_time = ? WHERE receiver_user_id = ? AND is_read = 0 AND is_deleted = 0 AND biz_type LIKE ?"
  } else {
    "UPDATE sys_message SET is_read = 1, update_time = ? WHERE receiver_user_id = ? AND is_read = 0 AND is_deleted = 0 AND biz_type LIKE ? AND id IN (\{message_in_clause(ids)})"
  }
  let params : Array[@moondb.Value] = [
    @moondb.Text(@core.now_str()),
    @moondb.Int64(receiver_id),
    @moondb.Text(biz_pat),
  ]
  for id in ids {
    params.push(@moondb.Int64(id))
  }
  let _ = x(conn, sql, params)
  conn.close()
}

///|
pub impl @dao.MessageDao for MessageRepository with fn remove_mine(self, receiver_id, biz_pat, ids) {
  let conn = open_conn(self.base.config)
  errdefer close_conn(conn)
  let sql = if ids.is_empty() {
    "UPDATE sys_message SET is_deleted = 1, update_time = ? WHERE receiver_user_id = ? AND is_deleted = 0 AND biz_type LIKE ?"
  } else {
    "UPDATE sys_message SET is_deleted = 1, update_time = ? WHERE receiver_user_id = ? AND is_deleted = 0 AND biz_type LIKE ? AND id IN (\{message_in_clause(ids)})"
  }
  let params : Array[@moondb.Value] = [
    @moondb.Text(@core.now_str()),
    @moondb.Int64(receiver_id),
    @moondb.Text(biz_pat),
  ]
  for id in ids {
    params.push(@moondb.Int64(id))
  }
  let _ = x(conn, sql, params)
  conn.close()
}

pub extend MessageRepository with @dao.MessageDao::{
  count_unread,
  count_unread_group,
  set_read,
  remove_mine,
}
