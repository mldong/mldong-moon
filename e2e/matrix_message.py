# -*- coding: utf-8 -*-
# 站内信矩阵（~26 例）——CRUD + 接收人隔离 + appCode 端隔离 + setRead/未读计数；boot2 8 端点黑盒
import json,urllib.request,os
B=os.environ.get('BASE','http://127.0.0.1:18680')
def post(path,body,token=None,headers=None):
    r=urllib.request.Request(B+path,data=json.dumps(body).encode(),method='POST')
    r.add_header('Content-Type','application/json')
    if token: r.add_header('Authorization','Bearer '+token)
    for k,v in (headers or {}).items(): r.add_header(k,v)
    try:
        with urllib.request.urlopen(r) as resp: return json.load(resp)
    except urllib.error.HTTPError as e:
        try: return json.load(e)
        except: return {'code':e.code}
ok=0;bad=0
def check(name,cond,detail=''):
    global ok,bad
    if cond: ok+=1; print('PASS',name,detail)
    else: bad+=1; print('FAIL',name,detail)

t=post('/sys/login',{'userName':'superAdmin','password':'123456'})['data']['token']
MYID='1'  # superAdmin id（字符串——id 一旦 int() 化会以 JSON 数字上送丢精度）
r=post('/sys/user/info',{},t)
if r['code']==0 and r['data'].get('id'): MYID=r['data']['id']
BT='platform_MMSG'+os.urandom(3).hex()   # 本轮 bizType 标记（平台域前缀 + 自清理圈）
FAKE_RUID=99999988888           # 不存在的接收人（隔离断言用）
created=[]
def mkmsg(title,biz,ruid=None,ext=None,token=None,hdr=None):
    body={'title':title,'content':'内容'+title,'msgType':20,'bizType':biz,'receiverUserId':ruid if ruid is not None else MYID}
    if ext is not None: body['ext']=ext
    r=post('/sys/message/save',body,token or t,hdr)
    if r['code']==0: created.append(r['data'])
    return r

# ── A. CRUD + ext 往返 ──
r=mkmsg('A1标题',BT+'_a',ext={'i18n':{'zh-CN':'中文'},'k':1})
check('A1 save 返回 id 串', r['code']==0 and isinstance(r['data'],str), str(r)[:80])
mid=r['data']
r=post('/sys/message/detail',{'id':mid},t)
check('A2 detail ext 往返', r['code']==0 and r.get('data') and r['data'].get('ext')=={'i18n':{'zh-CN':'中文'},'k':1}, str(r)[:160])
check('A3 detail 字段形状', r['data']['title']=='A1标题' and r['data']['msgType']==20 and r['data']['isRead']==0 and r['data']['senderUserId']==str(MYID), str(r['data'])[:120])
r=post('/sys/message/update',{'id':mid,'title':'A1改','content':'x','msgType':20,'bizType':BT+'_a','receiverUserId':MYID},t)
check('A4 update', r['code']==0)
r=post('/sys/message/detail',{'id':mid},t)
check('A5 update 回读', r['data']['title']=='A1改')
# save 缺 msgType → 契约必填（boot2 @NotNull 同位）；参数校验失败按契约 00-全局约定 §1 出 99999999
r=post('/sys/message/save',{'title':'A6缺类型','bizType':BT+'_d','receiverUserId':MYID},t)
check('A6 缺 msgType 拒绝 99999999', r['code']==99999999, str(r)[:80])

# ── B. page + 接收人隔离 ──
r=mkmsg('B1隔离','x_biz',ruid=FAKE_RUID)  # 发给不存在的人
r=post('/sys/message/page',{'pageNum':1,'pageSize':50},t)
rows=r['data']['rows']; mine=[x for x in rows if x['id']==mid]
check('B1 page 五键+行形状', r['code']==0 and all(k in r['data'] for k in ('pageNum','pageSize','recordCount','totalPage','rows')), '')
if mine:
    check('B2 行 id(str)/title/isRead', isinstance(mine[0]['id'],str) and all(k in mine[0] for k in ('title','isRead')))
else:
    check('B2 行 id(str)/title/isRead', False, 'own message not in page')
check('B3 接收人隔离（别人的消息不可见）', all(x['receiverUserId']==str(MYID) for x in rows), str({x['id']:x['receiverUserId'] for x in rows[:3]}))

# ── C. appCode 端隔离 + bizTypes 前缀自动补 ──
HDR_APP={'appCode':'e2eapp'}
r=post('/sys/message/save',{'title':'C1应用端','content':'x','msgType':20,'bizType':'c_biz','receiverUserId':MYID},t,HDR_APP)
cmsg=r['data'] if r['code']==0 else None
if cmsg: created.append(cmsg)
r=post('/sys/message/detail',{'id':cmsg},t) if cmsg else {'code':-1}
check('C1 appCode 域 save bizType 自动补前缀', r.get('code')==0 and r['data']['bizType']=='e2eapp_c_biz', str(r.get('data',{}).get('bizType')))
r=post('/sys/message/page',{'pageNum':1,'pageSize':50},t,HDR_APP)
app_rows=[x for x in r['data']['rows'] if x['id']==cmsg]
check('C2 appCode 域 page 可见', len(app_rows)==1)
r=post('/sys/message/page',{'pageNum':1,'pageSize':50},t)
plat_rows=[x for x in r['data']['rows'] if x['id']==cmsg]
check('C3 平台域 page 不可见（端隔离）', len(plat_rows)==0)
# bizTypes 单选自动补前缀（平台域）
r=post('/sys/message/page',{'pageNum':1,'pageSize':50,'bizTypes':[BT.replace('platform_','')+'_a']},t)
check('C4 bizTypes 单选过滤（自动补前缀）', r['code']==0 and r['data']['recordCount']==1 and r['data']['rows'][0]['bizType']==BT+'_a', str(r['data']['recordCount']))

# ── D. 未读计数 + setRead ──
r=post('/sys/message/getUnreadCount',{},t)
base_unread=r['data']
check('D1 getUnreadCount', r['code']==0 and isinstance(base_unread,int) and base_unread>=1, str(base_unread))
r=post('/sys/message/getUnreadCountGroupByBizType',{},t)
groups={g['bizType']:g['count'] for g in r['data']}
check('D2 分组形状 [{bizType,count}]', r['code']==0 and all(set(g.keys())=={'bizType','count'} for g in r['data']), str(r['data'])[:90])
check('D3 分组含本轮 bizType', groups.get(BT+'_a',0)>=1, str(groups))
# setRead 单条
r=post('/sys/message/setRead',{'ids':[mid]},t)
check('D4 setRead 单条', r['code']==0)
r=post('/sys/message/detail',{'id':mid},t)
check('D5 已读生效', r['data']['isRead']==1)
r=post('/sys/message/getUnreadCount',{},t)
check('D6 计数回落', r['data']==base_unread-1, f"{base_unread}->{r['data']}")
# 全部已读（平台域）
r=post('/sys/message/setRead',{'ids':[]},t)
check('D7 setRead 全部已读', r['code']==0)
r=post('/sys/message/getUnreadCount',{},t)
check('D8 平台域未读清零', r['data']==0, str(r['data']))
r=post('/sys/message/getUnreadCount',{},t,HDR_APP)
check('D9 appCode 域未读不受影响', r['data']>=1, str(r['data']))

# ── E. remove 本人域 + 清理 ──
r=post('/sys/message/remove',{'ids':[mid]},t)
check('E1 remove', r['code']==0)
if mid in created: created.remove(mid)
r=post('/sys/message/detail',{'id':mid},t)
check('E2 已删 detail 404 语义（99990002）', r['code']==99990002, str(r)[:60])
r=post('/sys/message/page',{'pageNum':1,'pageSize':50},t)
check('E3 删除后 page 不再出现', all(x['id']!=mid for x in r['data']['rows']))

# ── 清理（域隔离下 app 域消息须带 appCode 头删；remove 空 ids 拒绝是 boot2 同款，只有 setRead 允许空）──
if created:
    post('/sys/message/remove',{'ids':created},t)
    post('/sys/message/remove',{'ids':created},t,HDR_APP)
post('/sys/message/setRead',{'ids':[]},t,HDR_APP)
r=post('/sys/message/page',{'pageNum':1,'pageSize':50},t)
left=[x for x in r['data']['rows'] if x.get('bizType','').startswith(BT) or x.get('title','').startswith(('A1','A6','B1'))]
check('Z1 本轮消息清零', len(left)==0, str([x['id'] for x in left]))
r=post('/sys/message/page',{'pageNum':1,'pageSize':50},t,HDR_APP)
left_app=[x for x in r['data']['rows'] if x.get('bizType','').startswith('e2eapp')]
check('Z2 appCode 域清零', len(left_app)==0, str([x['id'] for x in left_app]))
print('OK %d FAIL %d'%(ok,bad))
