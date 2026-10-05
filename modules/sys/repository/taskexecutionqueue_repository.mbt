// sys_task_execution_queue MySQL 仓储 —— 业务端口薄实现，单表操作全委托 BaseDao 模板
// 〔cmd/gen 生成，可手改；重生成会覆盖本文件〕

///|
pub(all) struct TaskExecutionQueueRepository {
  base : BaseDao[@entity.TaskExecutionQueue]
}

///|
pub fn TaskExecutionQueueRepository::make(config : @core.MysqlConfig) -> TaskExecutionQueueRepository {
  { base: { config, table: taskexecutionqueue_table } }
}

///|
pub impl @dao.TaskExecutionQueueDao for TaskExecutionQueueRepository with fn insert(self, d) {
  self.base.insert(d)
  d.id
}

///|
pub impl @dao.TaskExecutionQueueDao for TaskExecutionQueueRepository with fn update(self, d) {
  self.base.update_by_id(d)
}

///|
pub impl @dao.TaskExecutionQueueDao for TaskExecutionQueueRepository with fn remove_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.remove_by_ids(vals)
}

///|
pub impl @dao.TaskExecutionQueueDao for TaskExecutionQueueRepository with fn find_by_id(self, id) {
  self.base.find_by_id(L(id))
}

///|
pub impl @dao.TaskExecutionQueueDao for TaskExecutionQueueRepository with fn find_by_ids(self, ids) {
  let vals : Array[@core.SqlValue] = []
  for id in ids {
    vals.push(L(id))
  }
  self.base.find_by_ids(vals)
}

///|
pub impl @dao.TaskExecutionQueueDao for TaskExecutionQueueRepository with fn page(self, w, page_num, page_size) {
  self.base.page(w, page_num, page_size)
}

pub extend TaskExecutionQueueRepository with @dao.TaskExecutionQueueDao::{
  remove_by_ids,
  find_by_id,
  insert,
  update,
  page,
  find_by_ids,
}
