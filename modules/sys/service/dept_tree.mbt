// sys_dept 树装配 —— 纯函数（零 IO，可 moon test）：parent_id 内存建树，root=0（boot2 TreeTool 同语义）。
// 孤儿节点（parent 缺失/删除）挂回根，不丢数据。

///|
/// 部门树节点（dept 全字段 + children）
pub(all) struct DeptNode {
  dept : @entity.Dept
  children : Array[DeptNode]
}

///|
/// 平表 → 树（sort 已由取数层排好；同 parent 内保持入参序）
pub fn build_dept_tree(items : Array[@entity.Dept]) -> Array[DeptNode] {
  let by_parent : Map[String, Array[@entity.Dept]] = Map([], capacity=0)
  let ids : Map[String, Bool] = Map([], capacity=0)
  for d in items {
    let _ = ids.set(d.id.to_string(), true)
  }
  for d in items {
    // 父不在集合内（含 root parent_id=0）→ 根组
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
