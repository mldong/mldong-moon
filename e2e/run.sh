#!/bin/bash
# mldong-moon 黑盒回归矩阵（真库）——十六套 e2e 用例总入口
#
# 前置：
#   1. mysql -u root -p < doc/sql/mysql-schema-all.sql （一次）
#   2. export MLDONG_DB_* && moon run --target wasm cmd/main   （另窗口起服务）
#   3. 本脚本：BASE=http://127.0.0.1:18680 bash e2e/run.sh
#
# 口径：用例即脚本（黑盒 HTTP，Python 标准库零依赖）；断言失败的用例会打 FAIL 行，
# 汇总行 "OK n FAIL m"；任何 FAIL>0 视为回归不绿。跑批产生的测试数据（mtest/v2user/
# holderu/genpost/gencfg 等前缀）脚本内自清理，残留可手动清。

set -u
cd "$(dirname "$0")"
export PYTHONIOENCODING=utf-8
TOTAL_OK=0; TOTAL_FAIL=0
for t in matrix_user.py pwdmatrix.py rotmatrix.py crud_smoke.py matrix_dept.py matrix_config.py matrix_holder.py matrix_dev.py matrix_dict.py matrix_menu.py matrix_message.py matrix_file.py matrix_lowcode.py matrix_rbac.py matrix_auth2.py matrix_batch2.py; do
  out=$(python "$t" 2>&1 | tail -1)
  echo "[$t] $out"
  ok=$(echo "$out" | grep -oE "OK [0-9]+" | grep -oE "[0-9]+" || echo 0)
  fail=$(echo "$out" | grep -oE "FAIL [0-9]+" | grep -oE "[0-9]+" || echo 0)
  TOTAL_OK=$((TOTAL_OK+ok)); TOTAL_FAIL=$((TOTAL_FAIL+fail))
done
echo "== 总计: OK $TOTAL_OK FAIL $TOTAL_FAIL"
[ "$TOTAL_FAIL" -eq 0 ]
