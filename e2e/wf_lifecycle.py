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

# ⑧ issues/146 缺口三集成侧落点：引擎事件 → async 监听器 → 站内信落库。
#    读回一律走框架自己的 /sys/message/page（biz_type 由 service 自动补 appCode 前缀 platform_，
#    直连 SQL 按 'wf_%' 过滤会查不到——本轮踩过：判据写错比功能没做更难发现）。
def wf_msgs(biz):
    r = post('/sys/message/page', {'pageNum': 1, 'pageSize': 20, 'bizType': 'platform_' + biz}, t)
    return ((r.get('data') or {}).get('rows') or []), r

task_rows, tr = wf_msgs('wf_task')
check('W8 wf 待办站内信落库且未读', len(task_rows) >= 1 and str(task_rows[0].get('isRead')) == '0', tr)
check('W9 wf 待办信发给参与者本人', all(
    str(x.get('receiverUserId')) == SUPER_ADMIN for x in task_rows), [x.get('receiverUserId') for x in task_rows])
inst_rows, ir = wf_msgs('wf_instance')
check('W10 wf 办结站内信落库（实例结束事件可达）', any(
    '已办结' in (x.get('title') or '') for x in inst_rows), ir)
# 自清：只删本套件读到的这些消息 id，别给共享库攒垃圾
del_ids = [str(x.get('id')) for x in (task_rows + inst_rows) if x.get('id')]
if del_ids:
    d = post('/sys/message/remove', {'ids': del_ids}, t)
    left, _ = wf_msgs('wf_task')
    check('W11 探针消息自清', d.get('code') == 0 and not left, left)

# ---- 非超管授权档（10-07 前端走查抓出的集成遗漏回归闸）----
# 超管走 is_super_admin 豁免，权限码前缀写错它照样绿；种子账号 u0010 挂 role「manage」。
# 负向码**从该账号现读的 permCode 里挑**（种子 sys_menu 有多行同码 wf:processTask:todoList，
# 按 sys_role_menu 反查"未授"会挑到其实已授的那条——现读 34 码里就含 todoList）：
# wf:processInstance:stats:overview 现读不在授权集内，且是只读端点，拿它当负向最稳。
try:
    tu = post('/sys/login', {'userName': 'u0010', 'password': '123456'})['data']['token']
    granted = post('/wf/processInstance/page', {'pageNum': 1, 'pageSize': 5}, tu)
    check('W12 授权账号调已授 wf 端点放行', granted.get('code') == 0, granted)
    denied = post('/wf/processInstance/stats/overview', {}, tu)
    check('W13 未授 wf 端点 99990406 且码带 wf: 前缀',
          denied.get('code') == 99990406
          and 'wf:processInstance:stats:overview' in (denied.get('msg') or ''), denied)
except Exception as e:  # 种子账号不在了也要报出来，别静默跳过
    check('W12/W13 非超管档可跑', False, e)

print('== wf_lifecycle: OK %d FAIL %d' % (ok, bad))
raise SystemExit(0 if bad == 0 else 1)
