# -*- coding: utf-8 -*-
import json,urllib.request,time
UNAME='v2user'+str(int(time.time())%100000)
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

# ---- 管理-状态族 ----
r=post('/sys/user/select',{'keywords':'u00'},t)
check('U1 select 3 条', r['code']==0 and len(r['data'])==3 and set(r['data'][0].keys())=={'label','value'}, str(r['data'])[:120])
r=post('/sys/user/save',{'userName':UNAME,'realName':'状态矩阵','mobilePhone':'13911112222'},t)
uid=r['data']; check('U0 save', r['code']==0)
r=post('/sys/user/locked',{'ids':[uid]},t)
check('U2 locked 200', r['code']==0)
r2=post('/sys/login',{'userName':UNAME,'password':'123456'})
check('U3 锁定后登录拒', r2['code']==99990401 and '锁定' in r2['msg'], str(r2))
r=post('/sys/user/unLocked',{'ids':[uid]},t)
check('U4 unLocked 200', r['code']==0)
r2=post('/sys/login',{'userName':UNAME,'password':'123456'})
check('U5 解锁后可登', r2['code']==0)
r=post('/sys/user/resetPassword',{'ids':[uid]},t)
check('U6 resetPassword 200', r['code']==0)
r2=post('/sys/login',{'userName':UNAME,'password':'123456'})
check('U7 重置后默认密码可登', r2['code']==0)

# ---- 个人中心族 ----
r=post('/sys/user/permCode',{},t)
check('U8 permCode 数组', r['code']==0 and isinstance(r['data'],list))
r=post('/sys/user/info',{},t)
check('U9 info 用户+角色+超管', r['code']==0 and r['data']['userName']=='superAdmin' and r['data']['superAdmin']==True and isinstance(r['data']['roleCodes'],list), str(r['data'])[:160])
r=post('/sys/user/updateInfo',{'realName':'超管改名','nickName':'昵称x','sex':1},t)
check('U10 updateInfo', r['code']==0)
r=post('/sys/user/info',{},t)
check('U11 info 回读新名', r['data']['realName']=='超管改名')
r=post('/sys/user/updateInfo',{'realName':'superAdmin'},t)  # 还原
r=post('/sys/user/updatePwd',{'oldPassword':'123456','newPassword':'abc12345'},t)
check('U12 updatePwd', r['code']==0)
r2=post('/sys/login',{'userName':'superAdmin','password':'abc12345'})
check('U13 新密可登', r2['code']==0)
r=post('/sys/user/updatePwd',{'oldPassword':'wrong','newPassword':'xyz98765'},t2 if False else r2['data']['token'])
check('U14 旧密错拒', r['code']==99990004, str(r))
t=post('/sys/login',{'userName':'superAdmin','password':'abc12345'})['data']['token']
r=post('/sys/user/updatePwd',{'oldPassword':'abc12345','newPassword':'123456'},t)  # 还原默认密码
check('U15 还原默认密码', r['code']==0)
r=post('/sys/user/updateAvatar',{'avatar':'https://cdn.example.com/a.png'},t)
check('U16 updateAvatar', r['code']==0)
r=post('/sys/user/info',{},t)
check('U17 info 带头像', r['data']['avatar']=='https://cdn.example.com/a.png')

# ---- 在线用户族 ----
r=post('/sys/user/onlineUserList',{},t)
d=r['data']
me=[x for x in d if x['userName']=='superAdmin']
check('U18 onlineUserList 有数据', r['code']==0 and len(d)>=1 and len(me)==1, 'rows=%d'%len(d))
if me:
    m=me[0]
    tok=m['tokenList'][0]
    check('U19 本人 token 明文+ip/ua', tok['tokenValue']==t and tok['isCurrentUser']==True and tok['loginIp']!='' and tok['loginBrowser']!='', 'ip=%s ua=%s'%(tok['loginIp'][:12],tok['loginBrowser'][:16]))
    check('U20 字段形状', set(tok.keys())=={'tokenValue','device','isCurrentUser','loginTime','loginTimestamp','expireTime','loginIp','loginBrowser','superAdmin'}, str(sorted(tok.keys())))
    check('U21 timeout>0', m['timeout']>0)
r=post('/sys/user/onlineUserList',{'keywords':'u0010'},t)
check('U22 keywords 过滤', r['code']==0 and all(x['userName']=='u0010' for x in r['data']) if r['data'] else True, str(r['data'])[:100])
r=post('/sys/user/onlineDevice',{},t)
check('U23 onlineDevice 自身行', r['code']==0 and len(r['data'])>=1 and all(x['isCurrentUser'] for x in r['data'] if x['tokenValue']==t))
r=post('/sys/user/info',{},'garbage-token')
check('U24 无效 token 401', r['code']==99990401)

print('OK %d FAIL %d'%(ok,bad))
