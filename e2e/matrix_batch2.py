# -*- coding: utf-8 -*-
# 管理面批矩阵：日志两表 CRUD5 / sms 模板+日志+发送四端点 / timer 内存态 9 端点 /
# 任务队列+历史 cancel/restore 往返（boot2 管理面同位；物理删表口径）
import json,urllib.request,time
import os
B=os.environ.get('BASE','http://127.0.0.1:18680')
def post(path,body,token=None,extra=None):
    req=urllib.request.Request(B+path,data=json.dumps(body).encode(),method='POST')
    req.add_header('Content-Type','application/json')
    if token: req.add_header('Authorization','Bearer '+token)
    if extra:
        for k,v in extra.items(): req.add_header(k,v)
    try:
        with urllib.request.urlopen(req) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        try: return json.load(e)
        except: return {'code':e.code}
ok=0;bad=0
def check(name,cond,detail=''):
    global ok,bad
    if cond: ok+=1; print('PASS',name,detail)
    else: bad+=1; print('FAIL',name,detail)

sa=post('/sys/login',{'userName':'superAdmin','password':'123456'})['data']
t=sa['token']
TAG='mb2-'+str(int(time.time())%100000)

def crud5(base, name_field, save_body, update_body, clean=True):
    """标准五端点往返：save→detail→page(m_ like)→update→remove；返回 (ok,fail,ids)"""
    r=post(f'{base}/save',save_body,t)
    assert r['code']==0, f'{base}/save: {r}'
    rid=r['data']
    r=post(f'{base}/detail',{'id':rid},t)
    c1=r['code']==0 and r['data']['id']==rid
    r=post(f'{base}/page',{'pageNum':1,'pageSize':5,('m_LIKE_'+name_field):TAG},t)
    c2=r['code']==0 and any(str(x['id'])==rid for x in r['data']['rows'])
    r=post(f'{base}/update',dict(update_body,id=rid),t)
    c3=r['code']==0
    r=post(f'{base}/remove',{'ids':[rid]},t)
    c4=r['code']==0
    r=post(f'{base}/detail',{'id':rid},t)
    c5=r['code']!=0  # 物理删表：detail 必查不到
    return c1 and c2 and c3 and c4 and c5

# ---- opLog CRUD5（无 is_deleted 物理删）----
r=crud5('/sys/opLog','name',{'name':TAG,'opType':1,'success':'1','message':'矩阵','ip':'127.0.0.1','url':'/sys/user/page','reqMethod':'POST','opTime':'2026-10-03 10:00:00','account':'superAdmin'},{'name':TAG+'-u'})
check('B1 opLog CRUD5 往返', r)

# ---- visLog CRUD5 ----
r=crud5('/sys/visLog','name',{'name':TAG,'success':'1','message':'矩阵','ip':'127.0.0.1','visType':1,'visTime':'2026-10-03 10:00:00','account':'superAdmin'},{'name':TAG+'-u','success':'1','visType':1})
check('B2 visLog CRUD5 往返', r)

# ---- smsTemplate CRUD5 + 唯一编码 ----
BIZ=91+(int(time.time())%400)
# 清本套件历史残留（uk_biz_type_provider 会与上一轮同 bizType 撞）
_old=post('/sys/smsTemplate/page',{'pageNum':1,'pageSize':50,'m_LIKE_templateCode':'mb2-'},t)
_ids=[x['id'] for x in _old['data']['rows']]
if _ids: post('/sys/smsTemplate/remove',{'ids':_ids},t)
tid=post('/sys/smsTemplate/save',{'bizType':BIZ,'templateCode':TAG,'provider':'mock','content':'hello {name}','signature':'MB','enabled':1},t)['data']
r=post('/sys/smsTemplate/detail',{'id':tid},t)
c1=r['code']==0 and r['data']['templateCode']==TAG
r=post('/sys/smsTemplate/page',{'pageNum':1,'pageSize':5,'m_LIKE_templateCode':TAG},t)
c2=r['code']==0 and r['data']['recordCount']>=1
r=post('/sys/smsTemplate/update',{'id':tid,'bizType':BIZ,'templateCode':TAG,'provider':'mock','content':'hi {name}'},t)
c3=r['code']==0
r2=post('/sys/smsTemplate/save',{'bizType':BIZ,'templateCode':TAG+'x','provider':'mock','content':'dup'},t)
check('B3 smsTemplate CRUD5', c1 and c2 and c3, str(r2)[:80])
# 唯一编码冲突语义（boot2 抛 99999999，moon 对齐 Conflict 99990003 差异记文档）
check('B4 templateCode 重复非 0', r2['code']!=0, str(r2))

# ---- sms 发送四端点 ----
phone='139'+TAG[-8:]
r=post('/sys/sms/sendCode',{'phone':phone,'bizType':BIZ},t)
check('B5 sendCode 形状 {taskId}', r['code']==0 and str(r['data']['taskId']).isdigit(), str(r))
r=post('/sys/sms/sendCode',{'phone':'','bizType':BIZ},t)
check('B6 sendCode 缺 phone 9999', r['code']!=0, str(r))
# 从日志取验证码（mock 通道内容回显）
r=post('/sys/smsLog/page',{'pageNum':1,'pageSize':10,'m_EQ_phone':phone},t)
log=r['data']['rows'][-1]
code=log['content'].split('：')[1].split('，')[0]
check('B7 smsLog 落行 provider=mock', log['provider']=='mock' and log['status']==1, str(log)[:120])
r=post('/sys/sms/verifyCode',{'phone':phone,'bizType':BIZ,'code':code},t)
check('B8 verifyCode 正确 true', r['code']==0 and r['data']==True, str(r))
r=post('/sys/sms/verifyCode',{'phone':phone,'bizType':BIZ,'code':code},t)
check('B9 verifyCode 一次性消费', r['code']==0 and r['data']==False, str(r))
r=post('/sys/sms/verifyCode',{'phone':phone,'bizType':BIZ,'code':'000000'},t)
check('B10 verifyCode 错码 false', r['code']==0 and r['data']==False, str(r))
r=post('/sys/sms/sendNotification',{'phone':phone,'bizType':BIZ,'params':{'name':'mtest'}},t)
c=r['code']==0 and r['data']['success']==True and str(r['data']['taskId']).isdigit()
check('B11 sendNotification 模板渲染', c, str(r))
r=post('/sys/smsLog/page',{'pageNum':1,'pageSize':10,'m_EQ_phone':phone},t)
check('B12 通知内容渲染 {name}', any('mtest' in x['content'] for x in r['data']['rows']), str(r['data']['rows'])[:120])
r=post('/sys/sms/batchSendNotification',{'phones':['138'+TAG[-8:],'138'+TAG[-8:]+'1'],'bizType':BIZ,'params':{'name':'mbatch'}},t)
check('B13 batchSend 逐 phone 数组', r['code']==0 and len(r['data'])==2 and all(x['success'] for x in r['data']), str(r)[:150])
r=post('/sys/smsLog/page',{'pageNum':1,'pageSize':1,'m_EQ_templateCode':'__nope__'},t)
# smsLog remove 清场（收发送样例行）
r=post('/sys/smsLog/page',{'pageNum':1,'pageSize':20,'m_LIKE_phone':phone},t)
ids=[x['id'] for x in r['data']['rows']]
if ids:
    post('/sys/smsLog/remove',{'ids':ids},t)
post('/sys/smsTemplate/remove',{'ids':[tid]},t)
check('B14 清理完成', True)

# ---- timer 内存态 9 端点 ----
TNAME='mtimer-'+str(int(time.time())%100000)
r=post('/sys/timer/save',{'timerName':TNAME,'actionClass':'com.mldong.mtest.Runner','cron':'0/10 * * * * ?','remark':'矩阵'},t)
tid2=r['data']
check('B15 timer save 默认停止', r['code']==0 and str(tid2).isdigit(), str(r))
r=post('/sys/timer/detail',{'id':tid2},t)
check('B16 timer detail state=2', r['code']==0 and r['data']['state']==2, str(r))
r2=post('/sys/timer/save',{'timerName':TNAME,'actionClass':'x','cron':''},t)
check('B17 timer 重名拒绝', r2['code']!=0, str(r2))
post('/sys/timer/start',{'id':tid2},t)
r=post('/sys/timer/detail',{'id':tid2},t)
check('B18 start state=1', r['data']['state']==1, str(r['data']))
post('/sys/timer/update',{'id':tid2,'remark':'改','redisCron':'0/20 * * * * ?'},t)
post('/sys/timer/stop',{'id':tid2},t)
r=post('/sys/timer/detail',{'id':tid2},t)
check('B19 update+stop', r['data']['remark']=='改' and r['data']['state']==2 and r['data']['redisCron']=='0/20 * * * * ?', str(r['data']))
post('/sys/timer/reset',{'ids':[tid2]},t)
r=post('/sys/timer/detail',{'id':tid2},t)
check('B20 reset redisCron 回落 cron', r['data']['redisCron']==r['data']['cron'], str(r['data']))
r=post('/sys/timer/page',{'pageNum':1,'pageSize':5,'keywords':TNAME},t)
check('B21 page keywords 过滤', r['code']==0 and r['data']['recordCount']==1, str(r)[:100])
r=post('/sys/timer/executeImmediate',{'id':tid2},t)
check('B22 executeImmediate 幂等 0', r['code']==0, str(r))
post('/sys/timer/remove',{'ids':[tid2]},t)
r=post('/sys/timer/detail',{'id':tid2},t)
check('B23 remove 后 NotFound', r['code']!=0, str(r))

# ---- 任务队列/历史 cancel/restore 往返 ----
r=post('/sys/taskExecutionQueue/save',{'taskName':TAG,'springBeanName':'mtestBean','bizId':'1686404946814533633','taskState':0,'allowMaxErrorCount':3,'variable':'{}'},t)
qid=r['data']
check('B24 queue save', r['code']==0 and str(qid).isdigit(), str(r))
r=post('/sys/taskExecutionQueue/cancelTask',{'id':qid,'cancelReason':'矩阵取消'},t)
check('B25 cancelTask 0', r['code']==0, str(r))
r=post('/sys/taskExecutionHistory/page',{'pageNum':1,'pageSize':2,'m_LIKE_taskName':TAG},t)
h=r['data']['rows'][0]
check('B26 转历史 state=3 同 id', h['taskState']==3 and h['errorReason']=='矩阵取消' and h['id']==qid, str(h)[:140])
r=post('/sys/taskExecutionQueue/detail',{'id':qid},t)
check('B27 队列行已删', r['code']!=0, str(r))
r=post('/sys/taskExecutionHistory/restore',{'id':qid},t)
check('B28 restore 0', r['code']==0, str(r))
r=post('/sys/taskExecutionQueue/page',{'pageNum':1,'pageSize':2,'m_LIKE_taskName':TAG},t)
q=r['data']['rows'][0]
check('B29 重排队 state=0 新 id', q['taskState']==0 and q['errorCount']==0 and q['id']!=qid, str(q)[:140])
post('/sys/taskExecutionQueue/remove',{'ids':[q['id']]},t)
post('/sys/taskExecutionHistory/remove',{'ids':[qid]},t)
r=post('/sys/taskExecutionHistory/detail',{'id':qid},t)
check('B30 清理完成', r['code']!=0, str(r))

print('OK %d FAIL %d'%(ok,bad))
