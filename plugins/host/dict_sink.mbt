// 插件向框架字典面贡献条目的落点（issues/146 集成轮 · UC-0432 注册中心契约）。
// 两档分别落到框架既有的两条腿：
//   expose → 装载器侧的活数组，cmd/main 把它包成 custom_providers 之一注进 DictServiceImpl
//            （custom_list 每次请求现聚合 ⇒ "清单请求时派生"原则②，插件 initialize 晚注册也看得见）；
//   answer → 框架 EnumDictRegistry（getByDictType 的回退腿之一；enum_list 才是它的清单），
//            即"只应答不曝光"——wf_*_handler 这 4 类运行时调度键归这一档。
// 幂等：同 dict_key 重复贡献覆盖原项——on_enable 每次启动都跑，不许越跑越多。

///|
pub(all) struct FrameworkDictSink {
  declared : Array[@core.DictModel]
  enums : @core.EnumDictRegistry
}

///|
pub fn FrameworkDictSink::new(enums : @core.EnumDictRegistry) -> FrameworkDictSink {
  { declared: [], enums }
}

///|
/// 请求时派生的曝光清单（copy 出一份，消费方改动不回写注册表）
pub fn FrameworkDictSink::list_declared(self : FrameworkDictSink) -> Array[@core.DictModel] {
  self.declared.copy()
}

///|
fn upsert(arr : Array[@core.DictModel], model : @core.DictModel) -> Unit {
  let mut hit = false
  for i, m in arr {
    if m.dict_key == model.dict_key {
      arr[i] = model
      hit = true
      break
    }
  }
  if !hit {
    arr.push(model)
  }
}

///|
pub impl @api.PluginDictApi for FrameworkDictSink with fn expose(
  self : FrameworkDictSink,
  model : @core.DictModel,
) -> Unit {
  upsert(self.declared, model)
}

///|
pub impl @api.PluginDictApi for FrameworkDictSink with fn answer(
  self : FrameworkDictSink,
  model : @core.DictModel,
) -> Unit {
  self.enums.register(model)
}

///|
pub extend FrameworkDictSink with @api.PluginDictApi::{expose, answer}
