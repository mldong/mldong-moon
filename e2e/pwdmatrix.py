import json,urllib.request,hashlib
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

# P1 正向：admin/123456
r=post('/sys/login',{'userName':'admin','password':'123456'})
check('P1 正向登录', r['code']==0 and r['data']['userId']=='1686404946814533633', str(r.get('code')))
# P2 错密：与不存在同话术
r2=post('/sys/login',{'userName':'admin','password':'wrong'})
r3=post('/sys/login',{'userName':'no_such_user','password':'x'})
check('P2 错密 401+99990401', r2['code']==99990401, str(r2))
check('P3 不存在同话术防枚举', r3['code']==99990401 and r3['msg']==r2['msg'])
# P4 锁定用户
r=post('/sys/login',{'userName':'superAdmin','password':'123456'})
t=r['data']['token']
# 用 SQL 锁 u0012 —— 这里先用错误路径验证缺字段
r5=post('/sys/login',{'userName':'admin'})
check('P5 缺 password 字段', r5['code']==99990401, str(r5.get('code')))
# P6 save 新用户 → 默认密码可登 → detail 不回显密文
r=post('/sys/user/save',{'userName':'pwdtest01','realName':'密码矩阵','mobilePhone':'13900001111'},t)
check('P6a save', r['code']==0, str(r))
uid=r['data']
r=post('/sys/login',{'userName':'pwdtest01','password':'123456'})
check('P6b 新用户默认密码可登', r['code']==0)
d=post('/sys/user/detail',{'id':uid},t)
dj=json.dumps(d,ensure_ascii=False)
check('P6c detail 不回显 password/salt', d['code']==0 and 'password' not in dj and 'salt' not in dj)
r=post('/sys/user/remove',{'ids':[uid]},t)
check('P6d 清理', r['code']==0)
# P7 rotate 回归（密码改动后登录→轮转链路）
r=post('/sys/login',{'userName':'superAdmin','password':'123456'})
r2=post('/sys/refreshToken',{'refreshToken':r['data']['refreshToken']})
check('P7 rotate 回归', r2['code']==0)
print('OK %d FAIL %d'%(ok,bad))
