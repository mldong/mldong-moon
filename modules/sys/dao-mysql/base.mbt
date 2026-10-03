// BaseDao[T] —— 单表通用操作模板（BaseMapper 式）：由表编解码器驱动，一次实现全表复用；
// 业务怎么组合由 service/dao 端口说了算。无反射的代价 = 每实体手写一份 TableCodec
//（后续 gen 代码生成器补齐这块样板）

///|
/// 列编解码：name=列名；get=实体取值（返回 N 表示该列不写）；default=NULL 时实体取的缺省
pub(all) struct ColCodec[T] {
  name : String
  get : (T) -> @core.SqlValue
}

///|
/// 表编解码器
pub(all) struct TableCodec[T] {
  name : String
  /// 参与读的列（SELECT 列清单，按序对应 from_row）
  cols : Array[String]
  /// 参与写的列（INSERT；UPDATE 用 update_cols）
  insert_cols : Array[ColCodec[T]]
  /// 参与更新的列（updateById 语义：get 返回 N 的列不覆盖）
  update_cols : Array[ColCodec[T]]
  /// 行 → 实体（按列名取）
  from_row : (@moondb.Row) -> T
  /// 主键取值
  id_of : (T) -> @core.SqlValue
  /// 逻辑删除列名（None = 物理删）
  del_col : String?
  /// 默认排序列（分页用；空则按主键倒序）
  order_col : String
}

///|
pub struct BaseDao[T] {
  config : @core.MysqlConfig
  table : TableCodec[T]
}

///|
/// 逻辑删过滤条件（del_col 配置时自动追加 del_col = 0）
fn[T] BaseDao::base_where(self : BaseDao[T]) -> @core.Wrapper {
  let w = @core.where_()
  if self.table.del_col is Some(col) {
    let _ = w.eq(col, @core.I(0))
  }
  w
}

///|
async fn[T] BaseDao::exec(self : BaseDao[T], sql : String, params : Array[@core.SqlValue]) -> @moondb.ExecResult raise @core.MldongError {
  let conn = open_conn(self.config)
  let r = x(conn, sql, to_db_values(params))
  conn.close()
  r
}

///|
async fn[T] BaseDao::query(self : BaseDao[T], sql : String, params : Array[@core.SqlValue]) -> Array[@moondb.Row] raise @core.MldongError {
  let conn = open_conn(self.config)
  let rows = q(conn, sql, to_db_values(params))
  conn.close()
  rows
}

///|
/// 单行查询（无行返回 None）
async fn[T] BaseDao::query_one(self : BaseDao[T], sql : String, params : Array[@core.SqlValue]) -> T? raise @core.MldongError {
  let rows = self.query(sql, params)
  if rows.is_empty() {
    None
  } else {
    Some((self.table.from_row)(rows[0]))
  }
}

///|
/// INSERT（主键取实体 id_of，雪花由 service 预生成）
async fn[T] BaseDao::insert(self : BaseDao[T], t : T) -> Unit raise @core.MldongError {
  let pairs : Array[@core.SetPair] = []
  for c in self.table.insert_cols {
    pairs.push(@core.SetPair::{ col: c.name, val: (c.get)(t) })
  }
  let (sql, params) = @core.build_insert(self.table.name, pairs)
  let _ = self.exec(sql, params)
}

///|
/// UPDATE BY 主键（update_cols 里值为 N 的列不覆盖，MyBatis-Plus updateById 语义）
async fn[T] BaseDao::update_by_id(self : BaseDao[T], t : T) -> Unit raise @core.MldongError {
  let pairs : Array[@core.SetPair] = []
  for c in self.table.update_cols {
    pairs.push(@core.SetPair::{ col: c.name, val: (c.get)(t) })
  }
  let w = @core.where_().eq("id", (self.table.id_of)(t))
  let (sql, params) = @core.build_update(self.table.name, pairs, w)
  let _ = self.exec(sql, params)
}

///|
/// 删除：del_col 配置=逻辑删（set del_col=1），否则物理删
async fn[T] BaseDao::remove_by_ids(self : BaseDao[T], ids : Array[@core.SqlValue]) -> Unit raise @core.MldongError {
  let w = @core.where_().in_("id", ids)
  let (sql, params) = match self.table.del_col {
    Some(col) =>
      // 复用 build_update：先补 del_col 的 SET，再拼 IN 条件
      @core.build_update(
        self.table.name,
        [@core.SetPair::{ col, val: @core.I(1) }],
        w,
      )
    None => @core.build_delete(self.table.name, w)
  }
  let _ = self.exec(sql, params)
}

///|
async fn[T] BaseDao::find_by_id(self : BaseDao[T], id : @core.SqlValue) -> T? raise @core.MldongError {
  let w = self.base_where().eq("id", id)
  let (sql, params) = @core.build_select(self.table.name, self.table.cols, w)
  self.query_one(sql, params)
}

///|
/// 条件查单条（无行 None）
async fn[T] BaseDao::find_one(self : BaseDao[T], w : @core.Wrapper) -> T? raise @core.MldongError {
  let full = self.base_where()
  for c in w.conds {
    full.conds.push(c)
  }
  let (sql, params) = @core.build_select(self.table.name, self.table.cols, full)
  self.query_one(sql, params)
}

///|
/// 条件查列表
async fn[T] BaseDao::list(self : BaseDao[T], w : @core.Wrapper) -> Array[T] raise @core.MldongError {
  let full = self.base_where()
  for c in w.conds {
    full.conds.push(c)
  }
  let (sql, params) = @core.build_select(
    self.table.name,
    self.table.cols,
    full,
    orders=[(self.order_col_of(), true)],
  )
  let rows = self.query(sql, params)
  let out : Array[T] = []
  for r in rows {
    out.push((self.table.from_row)(r))
  }
  out
}

///|
/// 计数
async fn[T] BaseDao::count(self : BaseDao[T], w : @core.Wrapper) -> Int raise @core.MldongError {
  let full = self.base_where()
  for c in w.conds {
    full.conds.push(c)
  }
  let (where_sql, params) = full.build()
  let rows = self.query(
    "SELECT COUNT(*) AS cnt FROM \{self.table.name} \{where_sql}",
    params,
  )
  row_i64(rows[0], "cnt").to_int()
}

///|
/// 分页：返回 (总数, 当页行)
async fn[T] BaseDao::page(
  self : BaseDao[T],
  w : @core.Wrapper,
  page_num : Int,
  page_size : Int,
) -> (Int, Array[T]) raise @core.MldongError {
  let total = self.count(w)
  let rows : Array[T] = []
  if total > 0 {
    let full = self.base_where()
    for c in w.conds {
      full.conds.push(c)
    }
    let (sql, params) = @core.build_select(
      self.table.name,
      self.table.cols,
      full,
      orders=[(self.order_col_of(), true)],
      limit=page_size,
      offset=(page_num - 1) * page_size,
    )
    for r in self.query(sql, params) {
      rows.push((self.table.from_row)(r))
    }
  }
  (total, rows)
}

///|
fn[T] BaseDao::order_col_of(self : BaseDao[T]) -> String {
  if self.table.order_col != "" {
    self.table.order_col
  } else {
    "id"
  }
}
