# -*- coding: utf-8 -*-
# jeeflow-moon 集成 · wf 生命周期冒烟（e2e 套件版）
# 链路：登录→设计保存→部署→getLastByName→发起（自动完成申请节点）→待办→审批→待办清零
# 断言注意：待办清零判定用"本流程实例的任务数"，库中可能有其他轮次的历史待办（buka 旧数据）。
# 造的数据带 moonsmoke4 前缀，结束自清（设计行 + 实例行保留供巡检，清 role/design 即可复跑）。
import json, os, time, urllib.request

B = os.environ.get('BASE', 'http://127.0.0.1:18680')
SUPER_ADMIN = '1567738052492341249'  # superAdmin（供数快照里的真实 sys_user id）
FLOW_NAME = 'moonsmoke4'
ok = bad = 0

def check(name, cond, detail=''):
    global ok, bad
    if cond:
        ok += 1
        print('PASS', name)
    else:
        bad += 1
        print('FAIL', name, str(detail)[:160])

def post(path, body, token=None):
    req = urllib.request.Request(B + path, data=json.dumps(body).encode(), method='POST')
    req.add_header('Content-Type', 'application/json')
    if token:
        req.add_header('Authorization', 'Bearer ' + token)
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)

t = post('/sys/login', {'userName': 'superAdmin', 'password': '123456'})['data']['token']
check('W0 login', bool(t))

def wf(action, args):
    args = dict(args)
    args['operator'] = SUPER_ADMIN
    return post('/wf/' + action, args, t)

# ① 设计保存（snaker 四节点：start→apply(applicant)→task1(主管=superAdmin)→end）
flow = {
    "name": FLOW_NAME,
    "displayName": "moon wf 冒烟流程",
    "type": "approval",
    "instanceUrl": "/form/apply",
    "nodes": [
        {"id": "start", "type": "snaker:start", "x": 100, "y": 200,
         "properties": {"width": 50, "height": 50}, "text": {"value": "开始"}},
        {"id": "apply", "type": "snaker:task", "x": 200, "y": 200,
         "properties": {"width": 100, "height": 50, "form": "apply-form",
                        "assignee": "applicant", "taskType": 0, "performType": 0},
         "text": {"value": "发起申请"}},
        {"id": "task1", "type": "snaker:task", "x": 300, "y": 200,
         "properties": {"width": 100, "height": 50, "form": "audit-form",
                        "assignee": SUPER_ADMIN, "taskType": 0, "performType": 0},
         "text": {"value": "主管审批"}},
        {"id": "end", "type": "snaker:end", "x": 400, "y": 200,
         "properties": {"width": 50, "height": 50}, "text": {"value": "结束"}},
    ],
    # 连线用 edges/sourceNodeId/targetNodeId（引擎形状；paths/from/to 会被静默忽略 ⇒ 无连线不产任务）
    "edges": [
        {"id": "e0", "sourceNodeId": "start", "targetNodeId": "apply", "properties": {}},
        {"id": "e1", "sourceNodeId": "apply", "targetNodeId": "task1", "properties": {}},
        {"id": "e2", "sourceNodeId": "task1", "targetNodeId": "end", "properties": {}},
    ],
}
r = wf('processDesign/save', {'name': FLOW_NAME, 'displayName': flow['displayName'],
                              'type': 'approval', 'content': flow})
check('W1 design save', r.get('code') == 0, r)
did = (r.get('data') or {}).get('id')
check('W1b design id', bool(did) and did != '0', did)

# ② 部署 → 取 define
r = wf('processDesign/deploy', {'id': did})
check('W2 deploy', r.get('code') == 0, r)
r = wf('processDefine/getLastByName', {'processDefineName': FLOW_NAME})
check('W2b getLastByName', r.get('code') == 0, r)
data = r.get('data') or {}
rows = data.get('rows') if isinstance(data.get('rows'), list) else []
define_id = (rows[0].get('processDefineId') if rows else None) or data.get('id')
check('W2c define id', bool(define_id), define_id)

# ③ 发起（startAndExecute 自动完成申请节点）
r = wf('processInstance/startAndExecute', {'processDefineId': define_id,
                                           'f_nextNodeOperator': SUPER_ADMIN})
check('W3 start', r.get('code') == 0, r)
inst = (r.get('data') or {}).get('processInstanceId') if isinstance(r.get('data'), dict) else None
check('W3b instance id', bool(inst), inst)

# ④ 待办（主管节点 assignee=superAdmin，经 user_provider 供数快照解析）
r = wf('processTask/todoList', {'pageNum': 1, 'pageSize': 20})
allrows = (r.get('data') or {}).get('rows') or []
mine = [x for x in allrows if str(x.get('processInstanceId')) == str(inst)]
check('W4 todo has our task', r.get('code') == 0 and len(mine) == 1, (len(mine), len(allrows)))

# ⑤ 审批通过 → 实例应结束（本实例待办归零）
if mine:
    tid = mine[0].get('processTaskId') or mine[0].get('taskId') or mine[0].get('id')
    r = wf('processTask/execute', {'processTaskId': tid, 'approve': True,
                                   'f_nextNodeOperator': SUPER_ADMIN})
    check('W5 execute', r.get('code') == 0, r)
    r = wf('processTask/todoList', {'pageNum': 1, 'pageSize': 20})
    left = [x for x in ((r.get('data') or {}).get('rows') or [])
            if str(x.get('processInstanceId')) == str(inst)]
    check('W6 instance done', r.get('code') == 0 and len(left) == 0, left)
    # ⑦ 审批记录可查
    r = wf('processInstance/approvalRecord', {'id': inst})
    check('W7 approval record', r.get('code') == 0, r)
else:
    check('W5 execute', False, 'no task')

print('== wf_lifecycle: OK %d FAIL %d' % (ok, bad))
raise SystemExit(0 if bad == 0 else 1)
