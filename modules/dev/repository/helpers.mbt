// SqlValue 便捷构造（sys repository 同款；gen 表编解码器假定包内自带）

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
