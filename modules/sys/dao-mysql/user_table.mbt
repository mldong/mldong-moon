// sys_user 表编解码器 —— BaseDao 模板的每实体配置（gen 代码生成器将来产出的就是这份样板）

///|
/// sys_user 表：逻辑删除 is_deleted、默认排序 create_time；password/salt 可读（改密/校验用）
// 但出参装配层（dto/user_json）绝不回显；avatar 可读写（个人头像）
let user_table : TableCodec[@entity.User] = TableCodec::{
  name: "sys_user",
  cols: [
    "id", "user_name", "real_name", "nick_name", "avatar", "mobile_phone", "tel", "email", "sex",
    "admin_type", "is_locked", "dept_id", "remark", "create_time", "update_time", "is_deleted",
    "password", "salt",
  ],
  insert_cols: [
    { name: "id", get: fn(u) { L(u.id) } },
    { name: "user_name", get: fn(u) { S(u.user_name) } },
    { name: "real_name", get: fn(u) { S(u.real_name) } },
    { name: "nick_name", get: fn(u) { opt_s(u.nick_name) } },
    { name: "mobile_phone", get: fn(u) { opt_s(u.mobile_phone) } },
    { name: "tel", get: fn(u) { opt_s(u.tel) } },
    { name: "email", get: fn(u) { opt_s(u.email) } },
    { name: "sex", get: fn(u) { opt_i(u.sex) } },
    { name: "admin_type", get: fn(u) { opt_i(u.admin_type) } },
    { name: "is_locked", get: fn(u) { opt_i(u.is_locked) } },
    { name: "dept_id", get: fn(u) { opt_l(u.dept_id) } },
    { name: "remark", get: fn(u) { opt_s(u.remark) } },
    { name: "create_time", get: fn(u) { S(match u.create_time { Some(s) => s; None => @core.now_str() }) } },
    { name: "create_user", get: fn(u) { opt_l(u.create_user) } },
    { name: "update_user", get: fn(u) { opt_l(u.update_user) } },
    { name: "password", get: fn(u) { opt_s(u.password) } },
    { name: "salt", get: fn(u) { opt_s(u.salt) } },
  ],
  update_cols: [
    { name: "user_name", get: fn(u) { S(u.user_name) } },
    { name: "real_name", get: fn(u) { S(u.real_name) } },
    { name: "nick_name", get: fn(u) { opt_s(u.nick_name) } },
    { name: "avatar", get: fn(u) { opt_s(u.avatar) } },
    { name: "mobile_phone", get: fn(u) { opt_s(u.mobile_phone) } },
    { name: "tel", get: fn(u) { opt_s(u.tel) } },
    { name: "email", get: fn(u) { opt_s(u.email) } },
    { name: "sex", get: fn(u) { opt_i(u.sex) } },
    { name: "dept_id", get: fn(u) { opt_l(u.dept_id) } },
    { name: "remark", get: fn(u) { opt_s(u.remark) } },
    { name: "update_time", get: fn(_u) { S(@core.now_str()) } },
    { name: "update_user", get: fn(u) { opt_l(u.update_user) } },
  ],
  from_row: row_user,
  id_of: fn(u) { L(u.id) },
  del_col: Some("is_deleted"),
  order_col: "create_time",
}

///|
fn opt_s(v : String?) -> @core.SqlValue {
  match v {
    Some(s) => S(s)
    None => N
  }
}

///|
fn opt_i(v : Int?) -> @core.SqlValue {
  match v {
    Some(n) => I(n)
    None => N
  }
}

///|
fn opt_l(v : Int64?) -> @core.SqlValue {
  match v {
    Some(n) => L(n)
    None => N
  }
}

///|
/// 行映射按列名取 —— MyBatis resultMap 的手写对应物（avatar/password/salt 等骨架不回显）
fn row_user(r : @moondb.Row) -> @entity.User {
  {
    id: row_i64(r, "id"),
    user_name: row_text(r, "user_name", ""),
    real_name: row_text(r, "real_name", ""),
    nick_name: row_opt_text(r, "nick_name"),
    avatar: row_opt_text(r, "avatar"),
    password: row_opt_text(r, "password"),
    salt: row_opt_text(r, "salt"),
    mobile_phone: row_opt_text(r, "mobile_phone"),
    tel: row_opt_text(r, "tel"),
    email: row_opt_text(r, "email"),
    admin_type: row_opt_int(r, "admin_type"),
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
