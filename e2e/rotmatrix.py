import json,urllib.request
import os
B=os.environ.get('BASE','http://127.0.0.1:18680')
def post(path,body,token=None):
    req=urllib.request.Request(B+path,data=json.dumps(body).encode(),method='POST')
    req.add_header('Content-Type','application/json')
    if token: req.add_header('Authorization','Bearer '+token)
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

# RR1 正向：登录 → rotate → 新对
r=post('/sys/login',{'userName':'superAdmin','password':'123456'})
d=r['data']; check('RR0 login shape', r['code']==0 and set(d.keys())=={'token','refreshToken','userId'} and d['userId']=='1567738052492341249', str(sorted(d.keys())))
r1=post('/sys/refreshToken',{'refreshToken':d['refreshToken']})
check('RR1 rotate 200/新对', r1['code']==0 and r1['data']['token']!=d['token'] and r1['data']['refreshToken']!=d['refreshToken'] and r1['data']['userId']==d['userId'])
nd=r1['data']
# RR2 新 access 可用
c=post('/sys/user/page',{'pageNum':1,'pageSize':2},nd['token'])['code']
check('RR2 新 access 打受保护端点', c==0, 'code=%s'%c)
# RR3 旧 refresh 重放 → 99990410
c=post('/sys/refreshToken',{'refreshToken':d['refreshToken']})['code']
check('RR3 旧 refresh 重放 99990410', c==99990410, 'code=%s'%c)
# RR4 旧 access 已废 → 401
c=post('/sys/user/page',{'pageNum':1,'pageSize':2},d['token'])['code']
check('RR4 旧 access 99990401', c==99990401, 'code=%s'%c)
# RR5 垃圾 refreshToken → 99990410
c=post('/sys/refreshToken',{'refreshToken':'garbage-not-exist'})['code']
check('RR5 垃圾串 99990410', c==99990410, 'code=%s'%c)
# RR6 rotate 延续 extra：u0010(app1) 轮转后新 token 仍有 app1 权限
r=post('/sys/login',{'userName':'u0010','password':'123456'})  # u0010 当前只有 manage@platform（还原过），先造 app1 授权
# 不改库：直接验证 platform 侧——u0010 有 manage@platform，page 无 sys:user:page → rotate 后仍 403 才对（extra 存活的反证）
t1=post('/sys/refreshToken',{'refreshToken':r['data']['refreshToken']})['data']
c=post('/sys/user/page',{'pageNum':1,'pageSize':2},t1['token'])['code']
check('RR6a rotate 后 extra(appCode=platform) 存活（仍滤空 403）', c==99990403, 'code=%s'%c)
# RR6b 正证：超管 rotate 后仍超管（跨码 200）
r2=post('/sys/login',{'userName':'superAdmin','password':'123456'})
t2=post('/sys/refreshToken',{'refreshToken':r2['data']['refreshToken']})['data']
c=post('/sys/user/page',{'pageNum':1,'pageSize':2},t2['token'])['code']
check('RR6b 超管 rotate 后仍 200', c==0, 'code=%s'%c)
# RR7 登出联动：新 access 登出 → 其 refresh 随废 → rotate 99990410
r3=post('/sys/login',{'userName':'superAdmin','password':'123456'})
d3=r3['data']
post('/sys/logout',{},d3['token'])
c=post('/sys/refreshToken',{'refreshToken':d3['refreshToken']})['code']
check('RR7 登出后 refresh 联动失效 99990410', c==99990410, 'code=%s'%c)
# RR8 缺参负向：空 refreshToken → 99990410
c=post('/sys/refreshToken',{'refreshToken':''})['code']
check('RR8 空串 99990410', c==99990410, 'code=%s'%c)
print('OK %d FAIL %d'%(ok,bad))
