test "moondb 0.3 values keep dynamic row output" {
  let row = @moondb.Row::{
    columns: ["created_at", "amount", "payload", "uuid", "tags"],
    values: [
      @moondb.Time("2026-11-27T01:02:03.123456"),
      @moondb.Numeric("1.50"),
      @moondb.Json("{\"k\":1}"),
      @moondb.Uuid(b"\x00\x01\x02\x03"),
      @moondb.Array([@moondb.Int(1)]),
    ],
  }
  let cols = Map([
    ("created_at", "datetime"),
    ("amount", "decimal"),
    ("payload", "json"),
    ("uuid", "binary"),
    ("tags", "json"),
  ])
  let j = generic_row_to_json(row, cols)
  let obj = match j {
    Object(m) => m
    _ => abort("expected object")
  }
  assert_eq(@core.get_text(j, "createdAt").unwrap(), "2026-11-27 01:02:03")
  assert_eq(@core.get_text(j, "amount").unwrap(), "1.50")
  assert_eq(obj.get("payload").unwrap().stringify(), "{\"k\":1}")
  assert_eq(obj.get("uuid").unwrap().stringify(), "null")
  assert_eq(obj.get("tags").unwrap().stringify(), "null")
}

test "moondb 0.3 text values preserve row readers" {
  let row = @moondb.Row::{
    columns: ["t", "n", "j", "u", "a"],
    values: [
      @moondb.Time("2026-11-27T01:02:03"),
      @moondb.Numeric("1.50"),
      @moondb.Json("{\"k\":1}"),
      @moondb.Uuid(b"\x00\x01\x02\x03"),
      @moondb.Array([@moondb.Int(1)]),
    ],
  }
  assert_eq(row_text(row, "t", "missing"), "2026-11-27T01:02:03")
  assert_eq(row_text(row, "n", "missing"), "1.50")
  assert_eq(row_text(row, "j", "missing"), "{\"k\":1}")
  assert_eq(row_text(row, "u", "missing"), "missing")
  assert_eq(row_text(row, "a", "missing"), "missing")
}
