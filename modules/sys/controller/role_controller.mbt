// sys_role 控制器 —— 通用注册器 + 每实体处理闭包
// URL /sys/role/{save,remove,update,detail,page} 对齐 13 栈契约
// 权限码预留（guard 下一轮挂）：sys:role:save/remove/update/detail/page

///|
pub fn[T : @svc.RoleService] register_role(ctx : @mb.ModuleContext, svc : T) -> Unit raise {
  register_crud(
    ctx,
    "/sys/role",
    {
      save: async fn(body) -> Json raise @core.MldongError {
        let id = svc.save(@dto.parse_role_save(body))
        Json::string(id.to_string())
      },
      update: async fn(body) -> Unit raise @core.MldongError {
        svc.update(@dto.parse_role_update(body))
      },
      remove: async fn(body) -> Unit raise @core.MldongError {
        svc.remove_by_ids(ids_of(body))
      },
      detail: async fn(body) -> Json raise @core.MldongError {
        let id : Int64 = match @core.get_i64(body, "id") {
          Some(n) => n
          None => 0L
        }
        @dto.role_json(svc.find_by_id(id))
      },
      page: async fn(body) -> (Int, Int, Int, Array[Json]) raise @core.MldongError {
        let req = @dto.parse_role_page(body)
        let (total, rows) = svc.page(req)
        let arr : Array[Json] = []
        for r in rows {
          arr.push(@dto.role_json(r))
        }
        (req.page_num, req.page_size, total, arr)
      },
    },
  )
}
