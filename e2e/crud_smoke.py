import json,urllib.request
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
        except: return {'code':e.code,'raw':'http-error'}
ok=[];bad=[]
def check(name,cond,detail=''):
    (ok if cond else bad).append(name); print(('PASS' if cond else 'FAIL'),name,detail)

r=post('/sys/login',{'userName':'superAdmin','password':'123456'})  # 超管，跨全码
t=r['data']['token']; check('S0 login',r['code']==0 and r['data']['userId']=='1567738052492341249')
r=post('/sys/user/save',{'userName':'mtest01','realName':'矩阵冒烟','password':'123456','mobilePhone':'13800000001'},t)
uid=r.get('data') or {}; uid=uid.get('id') if isinstance(uid,dict) else uid
check('S1 save',r['code']==0 and uid,'id=%s'%uid)
r=post('/sys/user/page',{'pageNum':1,'pageSize':5,'keywords':'mtest01'},t)
rows=r['data']['rows'] if isinstance(r.get('data'),dict) else []
check('S2 page find',r['code']==0 and any(str(x.get('id'))==str(uid) for x in rows),'rows=%d'%len(rows))
r=post('/sys/user/update',{'id':uid,'userName':'mtest01','realName':'矩阵冒烟改'},t)
check('S3 update',r['code']==0)
rid=post('/sys/role/page',{'pageNum':1,'pageSize':10},t)['data']['rows'][0]['id']
r=post('/sys/user/grantRole',{'userId':uid,'roleIdList':[str(rid)]},t)
check('S4 grantRole',r['code']==0,'role=%s'%rid)
r=post('/sys/user/remove',{'ids':[str(uid)]},t)
check('S5 remove',r['code']==0)
r=post('/sys/user/page',{'pageNum':1,'pageSize':5,'keywords':'mtest01'},t)
rows=r['data']['rows'] if isinstance(r.get('data'),dict) else []
check('S6 removed',r['code']==0 and not rows)
print('OK %d FAIL %d'%(len(ok),len(bad)))
