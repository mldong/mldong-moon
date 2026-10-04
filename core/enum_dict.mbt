// 枚举字典注册中心 —— boot2 DictScanner / goframe RegisterEnumValues+GetEnums 同位：
// 框架件（core），main 建全进程一实例传各模块（ConfigHolder 同一条传链）；
// 声明跟枚举走——各模块在自己的 enums.mbt 里声明常量表，模块装配期调 register 灌入；
// 消费端（dict 服务 getByDictType 回退链 / enumDictList）只查注册中心。
// 与 custom 字典注册中心（custom_providers，UC-0432 原则①存服务不存模型）刻意分表：
// 枚举存模型快照、custom 存服务，goframe 亦是两张表。

///|
/// 枚举/自定义字典项模型（boot2 DictItemModel / goframe DictItemModelVO 同形；
/// dictItemValue 已按 dataType 定型：1=字符串 2=数值）
pub(all) struct DictItemModel {
  name : String
  dict_item_value : Json
  dict_item_key : String
  /// ext 预留（i18n 等）；None 不出键（UC-0426 ext 同语义）
  ext : Json?
}

///|
/// 枚举/自定义字典模型（boot2 DictModel / goframe DictModelVO 同形）：
/// dataType 整型 1|2（枚举路径必填，UC-0431① 播种器采集源）；自定义路径 None 不出键
pub(all) struct DictModel {
  name : String
  dict_key : String
  data_type : Int?
  items : Array[DictItemModel]
}

///|
pub(all) struct EnumDictRegistry {
  /// 清单序（注册序；重复 dict_key 覆盖原项不追加）
  models : Array[DictModel]
  /// 按 key 查表（getByDictType 回退链）
  by_key : Map[String, DictModel]
}

///|
pub fn EnumDictRegistry::new() -> EnumDictRegistry {
  { models: [], by_key: Map([], capacity=0) }
}

///|
/// 注册（重复 dict_key 覆盖原项——后写赢，装配期幂等）
pub fn EnumDictRegistry::register(self : EnumDictRegistry, model : DictModel) -> Unit {
  match self.by_key.get(model.dict_key) {
    Some(_) => {
      for i, m in self.models {
        if m.dict_key == model.dict_key {
          self.models[i] = model
          break
        }
      }
    }
    None => self.models.push(model)
  }
  let _ = self.by_key.set(model.dict_key, model)
}

///|
/// 全量清单（goframe GetEnums 同位）
pub fn EnumDictRegistry::list(self : EnumDictRegistry) -> Array[DictModel] {
  self.models
}

///|
/// 按 dict_key 查找（goframe FindInEnumMapModel 同位；无则 None → 回退链走下一级）
pub fn EnumDictRegistry::find(self : EnumDictRegistry, dict_key : String) -> DictModel? {
  self.by_key.get(dict_key)
}
