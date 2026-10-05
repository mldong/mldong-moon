// sys_dept 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait DeptService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.DeptSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.DeptSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.Dept raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.DeptPageReq) -> (Int, Array[@entity.Dept]) raise @core.MldongError
  /// 全量部门（树端点取数；sort 升序）——二次开发（树表）
  async fn list_all(Self, @core.Ctx) -> Array[@entity.Dept] raise @core.MldongError
  /// 自动排序（boot2 autoSort 同式：sort = 层级×10000 + 层内 DFS 序×1000）
  async fn auto_sort(Self, @core.Ctx) -> Unit raise @core.MldongError
  /// 批量拖拽排序（[{id,sort}] 逐行直更）
  async fn update_sort(Self, @core.Ctx, Array[(Int64, Int64)]) -> Unit raise @core.MldongError
}

///|
pub(all) struct DeptServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.DeptDao] DeptService for DeptServiceImpl[R] with fn save(self, ctx, req) {
  // 唯一编码校验（boot2 checkUnique 同位一行调）
  self.dao.check_unique(req.code, None, "唯一编码已存在: " + req.code)
  let d : @entity.Dept = {
    id: @core.next_id(),
    parent_id: req.parent_id,
    name: req.name,
    code: req.code,
    sort: req.sort,
    enabled: req.enabled,
    leader_ids: req.leader_ids,
    main_leader_id: req.main_leader_id,
    remark: req.remark,
    pids: None,
    variable: req.variable,
    create_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: Some(0),
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.DeptDao] DeptService for DeptServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 编码查重（排除自身）
  self.dao.check_unique(req.code, Some(req.id), "唯一编码已存在: " + req.code)
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.Dept = {
    id: req.id,
    parent_id: req.parent_id,
    name: req.name,
    code: req.code,
    sort: req.sort,
    enabled: req.enabled,
    leader_ids: req.leader_ids,
    main_leader_id: req.main_leader_id,
    remark: req.remark,
    pids: None,
    variable: req.variable,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: None,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.DeptDao] DeptService for DeptServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.DeptDao] DeptService for DeptServiceImpl[R] with fn find_by_id(
  self,
  _ctx,
  id,
) {
  match self.dao.find_by_id(id) {
    Some(d) => d
    None => raise @core.MldongError::NotFound("数据不存在: " + id.to_string())
  }
}

///|
pub impl[R : @dao.DeptDao] DeptService for DeptServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
///|
pub impl[R : @dao.DeptDao] DeptService for DeptServiceImpl[R] with fn list_all(self, _ctx) {
  self.dao.list_all()
}

///|
/// 自动排序：全量建树后 DFS，sort = 层级×10000 + 该层已访序×1000（boot2 autoSort 同式，
/// 层内计数器是全树共享的——不同父的同层节点也连续编号），逐行 update
pub impl[R : @dao.DeptDao] DeptService for DeptServiceImpl[R] with fn auto_sort(self, _ctx) -> Unit raise @core.MldongError {
  fn dfs(nodes : Array[DeptNode], level : Int, counters : Map[Int, Int], updates : Array[@entity.Dept]) -> Unit {
    for n in nodes {
      let idx = counters.get(level).unwrap_or(0)
      counters.set(level, idx + 1)
      n.dept.sort = Some((level * 10000 + idx * 1000).to_int64())
      updates.push(n.dept)
      dfs(n.children, level + 1, counters, updates)
    }
  }

  let counters : Map[Int, Int] = Map([], capacity=0)
  let updates : Array[@entity.Dept] = []
  dfs(build_dept_tree(self.dao.list_all()), 1, counters, updates)
  for d in updates {
    self.dao.update(d)
  }
}

///|
/// 批量拖拽排序：[{id,sort}] 按 id 查回实体后直更 sort（boot2 updateBatchById 同语义）
pub impl[R : @dao.DeptDao] DeptService for DeptServiceImpl[R] with fn update_sort(
  self,
  _ctx,
  items : Array[(Int64, Int64)],
) -> Unit raise @core.MldongError {
  if !items.is_empty() {
    let ids : Array[Int64] = []
    for it in items {
      ids.push(it.0)
    }
    let by_id : Map[Int64, @entity.Dept] = Map([], capacity=0)
    for d in self.dao.find_by_ids(ids) {
      by_id.set(d.id, d)
    }
    for it in items {
      match by_id.get(it.0) {
        Some(d) => {
          d.sort = Some(it.1)
          self.dao.update(d)
        }
        None => ()
      }
    }
  }
}

///|
/// 部门树节点（dept 全字段 + children）——二次开发（树表）
pub(all) struct DeptNode {
  dept : @entity.Dept
  children : Array[DeptNode]
}

///|
/// 平表 → 树（parent_id 内存建树，root=0，boot2 TreeTool 同语义；sort 已由取数层排好）。
/// 孤儿节点（父缺失/删除）挂回根，不丢数据。
pub fn build_dept_tree(items : Array[@entity.Dept]) -> Array[DeptNode] {
  let by_parent : Map[String, Array[@entity.Dept]] = Map([], capacity=0)
  let ids : Map[String, Bool] = Map([], capacity=0)
  for d in items {
    let _ = ids.set(d.id.to_string(), true)
  }
  for d in items {
    let key = match d.parent_id {
      Some(p) =>
        if p == 0L || ids.get(p.to_string()) is None {
          "0"
        } else {
          p.to_string()
        }
      None => "0"
    }
    match by_parent.get(key) {
      Some(arr) => arr.push(d)
      None => {
        let _ = by_parent.set(key, [d])
      }
    }
  }
  fn attach(d : @entity.Dept) -> DeptNode {
    let children = match by_parent.get(d.id.to_string()) {
      Some(arr) => arr.map(attach)
      None => []
    }
    { dept: d, children }
  }

  match by_parent.get("0") {
    Some(roots) => roots.map(attach)
    None => []
  }
}

pub extend DeptServiceImpl with DeptService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
  list_all,
  auto_sort,
  update_sort,
}
