// 树端点 —— /sys/dept/list（部门树）+ /sys/user/getDeptUserTree（部门用户树，boot2 同位）。
// 取数走闭包注入（dao 实现在 module.mbt 装配处接线），本文件零 dao-mysql 依赖；
// 生成器产物之外的手写扩展面，重生成不覆盖。

///|
/// dept_json 套 children（动态键并回 Object——boot2 DeptVO + children 形状）
///|
pub fn dept_tree_policy() -> @guard.RoutePolicy {
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/dept/list", ["sys:dept:list"]))
    .rule(@guard.RouteRule::make("/sys/user/getDeptUserTree", ["sys:user:getDeptUserTree"]))
}

///|
fn dept_node_json(n : @svc.DeptNode) -> Json {
  let base = match @dto.dept_json(n.dept) {
    Object(m) => m
    _ => Map([], capacity=0)
  }
  let arr : Array[Json] = []
  for c in n.children {
    arr.push(dept_node_json(c))
  }
  let _ = base.set("children", Json::array(arr))
  Json::object(base)
}

///|
/// 部门用户树节点（boot2 DeptUserTreeVO：label/value/nodeType/disabled/children）
fn dept_user_node(n : @svc.DeptNode, users_by_dept : Map[String, Array[Json]]) -> Json {
  let children : Array[Json] = []
  // 本部门用户（nodeType=2 叶子）
  match users_by_dept.get(n.dept.id.to_string()) {
    Some(users) =>
      for u in users {
        children.push(u)
      }
    None => ()
  }
  // 子部门（nodeType=1，disabled=true 不可选）
  for c in n.children {
    children.push(dept_user_node(c, users_by_dept))
  }
  {
    "label": Json::string(match n.dept.name {
      "" => "未命名部门"
      v => v
    }),
    "value": Json::string(n.dept.id.to_string()),
    "nodeType": Json::string("1"),
    "disabled": Json::boolean(true),
    "children": Json::array(children),
  }
}

///|
/// 树端点注册（dept_list/users 两个取数闭包由 module.mbt 接线）
pub fn[S : @port.TokenStore, P : @port.PermissionProvider] register_dept_trees(
  ctx : @mb.ModuleContext,
  dept_list : async () -> Array[@entity.Dept] raise @core.MldongError,
  users : async () -> Array[@entity.User] raise @core.MldongError,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  // 部门树（boot2 /sys/dept/list：全量平表 → 树）
  let list_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let items = dept_list()
    let tree = @svc.build_dept_tree(items)
    let arr : Array[Json] = []
    for n in tree {
      arr.push(dept_node_json(n))
    }
    @core.ok_data(Json::array(arr))
  })
  // 部门用户树（boot2 /sys/user/getDeptUserTree：部门节点挂用户叶子）
  let dept_user_tree_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let tree = @svc.build_dept_tree(dept_list())
    // 用户按部门分组（一次取全量，避免 boot2 逐部门 N 查）
    let users_by_dept : Map[String, Array[Json]] = Map([], capacity=0)
    for u in users() {
      let node : Json = {
        "label": Json::string(u.real_name),
        "value": Json::string(u.id.to_string()),
        "nodeType": Json::string("2"),
        "disabled": Json::boolean(false),
        "children": Json::array([]),
      }
      let key = match u.dept_id {
        Some(d) => d.to_string()
        None => continue
      }
      match users_by_dept.get(key) {
        Some(arr) => arr.push(node)
        None => {
          let _ = users_by_dept.set(key, [node])
        }
      }
    }
    let arr : Array[Json] = []
    for n in tree {
      arr.push(dept_user_node(n, users_by_dept))
    }
    @core.ok_data(Json::array(arr))
  })
  g.post(ctx, "/sys/dept/list", list_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/getDeptUserTree", dept_user_tree_handler) catch {
    e => raise e
  }
}
