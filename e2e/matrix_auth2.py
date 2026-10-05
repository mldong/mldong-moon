# -*- coding: utf-8 -*-
# 鉴权扩展矩阵：踢人四件套 / playUser 诚实报错 / captcha 三件套 + 登录联动开关闭环
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
UN='mauth'+str(int(time.time())%100000)

uid=post('/sys/user/save',{'userName':UN,'realName':'踢人矩阵','mobilePhone':'13900002222'},t)['data']
check('A1 user save', uid is not None)

def login():
    return post('/sys/login',{'userName':UN,'password':'123456'})['data']

# ---- 踢人四件套 ----
s1=login()
check('A2 新用户可登', s1 and s1.get('token'), str(s1)[:60])
r=post('/sys/user/logoutByTokenValue',{'ids':[s1['token']]},t)
r2=post('/sys/user/info',{},s1['token'])
check('A3 logoutByTokenValue 注销生效', r['code']==0 and r2['code']==99990403, str(r2))
s2=login()
r=post('/sys/user/kickoutByTokenValue',{'ids':[s2['token']]},t)
r2=post('/sys/user/info',{},s2['token'])
check('A4 kickoutByTokenValue 踢下线', r['code']==0 and r2['code']==99990403, str(r2))
s3=login()
r=post('/sys/user/logoutByLoginId',{'ids':[uid]},t)
r2=post('/sys/user/info',{},s3['token'])
check('A5 logoutByLoginId 全会话注销', r['code']==0 and r2['code']==99990403, str(r2))
s4=login()
r=post('/sys/user/kickoutByLoginId',{'ids':[uid]},t)
r2=post('/sys/user/info',{},s4['token'])
check('A6 kickoutByLoginId 全会话踢下线', r['code']==0 and r2['code']==99990403, str(r2))
r=post('/sys/user/logoutByTokenValue',{'ids':['bogus-token']},t)
check('A7 无效 token 幂等 0', r['code']==0, str(r))

# ---- 扮演往返（boot2 双会话同构：目标签真会话 + extra 盖操作者标记）----
r=post('/sys/playUser',{'userId':uid},t)
check('A8 playUser 发 token+refreshToken 对', r['code']==0 and r['data']['token'] and r['data']['refreshToken'], str(r))
pt=r['data']['token']
d=post('/sys/user/info',{},pt)['data']
check('A9 身份切换到目标 + ext.isPlayer', d['id']==uid and d.get('ext',{}).get('isPlayer')==True, str(d.get('ext')))
d2=post('/sys/user/info',{},t)['data']
check('A10 操作者会话未动且非扮演', d2['userName']=='superAdmin' and d2['ext']['isPlayer']==False, str(d2.get('ext')))
r2=post('/sys/unPlayUser',{},pt)
check('A11 unPlay 回跳操作者原 token', r2['code']==0 and r2['data']['token']==t, str(r2)[:100])
r3=post('/sys/user/info',{},pt)
check('A12 played token 已失效', r3['code']==99990403, str(r3))
r4=post('/sys/user/info',{},r2['data']['token'])
check('A13 操作者原会话重入 ok', r4['code']==0 and r4['data']['userName']=='superAdmin', str(r4)[:60])
r5=post('/sys/playUser',{'userId':'999'},t)
check('A14 目标不存在 99990002', r5['code']==99990002, str(r5))
r6=post('/sys/unPlayUser',{},t)
check('A15 非扮演会话 unPlay 非 0', r6['code']!=0, str(r6)[:80])

# ---- captcha 三件套（公开面）----
r=post('/sys/captcha',{},None)
check('A10 captcha 形状 uuid+svg-base64', r['code']==0 and r['data']['uuid'] and r['data']['base64'].startswith('data:image/svg+xml;base64,'), str(r['data'])[:80])
r=post('/sys/getCaptchaOpenFlag',{},None)
check('A11 getCaptchaOpenFlag 公开', r['code']==0 and r['data']['flag'] in (True,False), str(r))
r=post('/sys/getSm2PublicKey',{},None)
check('A12 getSm2PublicKey 空公钥', r['code']==0 and r['data']['publicKey']=='', str(r))

# ---- 验证码开关登录联动（开 → 缺验证码拒；关 → 恢复）----
cfg=post('/sys/config/page',{'pageNum':1,'pageSize':5,'m_EQ_code':'MOLE_CAPTCHA_OPEN'},t)
if cfg['data']['recordCount']>0:
    cid=cfg['data']['rows'][0]['id']
    r=post('/sys/config/update',{'id':cid,'name':'登录验证码开关','code':'MOLE_CAPTCHA_OPEN','groupCode':'','content':'true'},t)
else:
    r=post('/sys/config/save',{'name':'登录验证码开关','code':'MOLE_CAPTCHA_OPEN','groupCode':'','content':'true'},t)
    cid=r['data']
check('A13 开关置 true 0', r['code']==0, str(r))
r=post('/sys/getCaptchaOpenFlag',{},None)
check('A14 flag 实时 true', r['data']['flag']==True, str(r))
r2=post('/sys/login',{'userName':'superAdmin','password':'123456'})
check('A15 开启后缺验证码拒', r2['code']==99990401 and '验证码' in r2['msg'], str(r2))
r=post('/sys/config/update',{'id':cid,'name':'登录验证码开关','code':'MOLE_CAPTCHA_OPEN','groupCode':'','content':'false'},t)
r2=post('/sys/getCaptchaOpenFlag',{},None)
check('A16 关闭后恢复可登', r2['data']['flag']==False and post('/sys/login',{'userName':'superAdmin','password':'123456'})['code']==0, str(r2)[:80])

# ---- 清理 ----
post('/sys/user/remove',{'ids':[uid]},t)
r=post('/sys/user/detail',{'id':uid},t)
check('A17 清理', r['code']!=0 or r['data'] in (None,{}), str(r)[:60])

print('OK %d FAIL %d'%(ok,bad))
