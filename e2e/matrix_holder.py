# -*- coding: utf-8 -*-
import json,urllib.request,time
import os
B=os.environ.get('BASE','http://127.0.0.1:18680')
UN='holderu'+str(int(time.time())%100000)
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

t=post('/sys/login',{'userName':'superAdmin','password':'123456'})['data']['token']

# H1 基线：默认密码 123456（holder 无配置时回默认）
r=post('/sys/user/save',{'userName':UN,'realName':'holder验证','mobilePhone':'13877770001'},t)
uid=r['data']; check('H1 save 基线', r['code']==0)
r=post('/sys/login',{'userName':UN,'password':'123456'})
check('H2 默认 123456 可登', r['code']==0)

# H2 写配置 M_DEFAULT_PASSWORD=abc12345（holder 写路刷新）
r=post('/sys/config/save',{'name':'默认密码','code':'M_DEFAULT_PASSWORD','groupCode':'SYS','content':'abc12345'},t)
check('H3 写 M_DEFAULT_PASSWORD', r['code']==0)
r=post('/sys/user/save',{'userName':UN+'b','realName':'holder二段','mobilePhone':'13877770002'},t)
uidb=r['data']; check('H4 二段 save', r['code']==0)
r=post('/sys/login',{'userName':UN+'b','password':'abc12345'})
check('H5 新默认密码即时生效', r['code']==0, str(r))
r=post('/sys/login',{'userName':UN+'b','password':'123456'})
check('H6 旧默认密码不可登', r['code']==99990401)

# H3 查重抽查（三表 check_unique 行为不变）
r=post('/sys/config/save',{'name':'x','code':'M_DEFAULT_PASSWORD','groupCode':'SYS'},t)
check('H7 config 查重 99990003', r['code']==99990003)
r=post('/sys/dept/save',{'name':'hx','code':'holderdept','parentId':'0'},t)
did=r['data']
r=post('/sys/dept/save',{'name':'hx2','code':'holderdept','parentId':'0'},t)
check('H8 dept 查重 99990003', r['code']==99990003)
r=post('/sys/post/save',{'name':'hx','code':'holderpost'},t)
pid=r['data']
r=post('/sys/post/save',{'name':'hx2','code':'holderpost'},t)
check('H9 post 查重 99990003', r['code']==99990003)
r=post('/sys/post/update',{'id':pid,'name':'hx','code':'holderpost'},t)
check('H10 查重排除自身（update 自身过）', r['code']==0)

# H4 还原：删配置回默认 + 清理
r=post('/sys/config/remove',{'ids':[r['data']]},t) if False else None
r=post('/sys/config/page',{'pageNum':1,'pageSize':5,'m_EQ_code':'M_DEFAULT_PASSWORD'},t)
cfgid=r['data']['rows'][0]['id']
post('/sys/config/remove',{'ids':[cfgid]},t)
r=post('/sys/user/save',{'userName':UN+'c','realName':'holder三段','mobilePhone':'13877770003'},t)
uidc=r['data']
r=post('/sys/login',{'userName':UN+'c','password':'123456'})
check('H11 删配置回默认 123456', r['code']==0)
# 清理
post('/sys/user/remove',{'ids':[uid,uidb,uidc]},t)
post('/sys/dept/remove',{'ids':[did]},t)
post('/sys/post/remove',{'ids':[pid]},t)
print('OK %d FAIL %d'%(ok,bad))
