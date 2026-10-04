// dto 出参小助手（sys dto 同款；gen 模板假定包内自带，首个非 sys 模块补齐这份）

///|
fn jstr(v : String?) -> Json {
  match v {
    Some(s) => Json::string(s)
    None => Json::null()
  }
}

///|
fn jint(v : Int?) -> Json {
  match v {
    Some(n) => Json::number(n.to_double())
    None => Json::null()
  }
}

///|
/// 雪花 id 一律字符串化（JS Number 53 位精度装不下 64 位雪花，同款坑统一修）
fn jsnow(v : Int64?) -> Json {
  match v {
    Some(n) => Json::string(n.to_string())
    None => Json::null()
  }
}
