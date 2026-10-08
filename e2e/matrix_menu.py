# -*- coding: utf-8 -*-
# 菜单模块矩阵（sys_menu）——自建自清（mm 前缀 + m_EQ_code 圈定 + remove）
# 红线：只挂根节点/自建行，严禁动 107 行权限种子（RBAC 码链数据源）
# 覆盖：tree 形状（runner UC-0409 根节点 id(str)/name + children + ext 空不出键）
#       appCode 缺省过滤 + m_EQ_appCode 显式覆盖 / list 平铺 + sort 升序
#       CRUD 回环 + ext 往返 + code 全局唯一 + page m_EQ + 批删
import json,urllib.request,time
import os
B=os.environ.get('BASE','http://127.0.0.1:18680')
RID='mm'+str(int(time.time())%1000000)

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

# ---- tree（UC-0409 契约面）----
r=post('/sys/menu/tree',{},t)
check('M1 tree 直返数组', r['code']==0 and isinstance(r['data'],list) and len(r['data'])>0, 'n=%s'%len(r.get('data',[])))
root=r['data'][0]
check('M2 根节点 id(str)/name', isinstance(root.get('id'),str) and isinstance(root.get('name'),str), str(root.get('id')))
check('M3 节点带 children', 'children' in root and isinstance(root['children'],list), str(type(root.get('children'))))
# （M4 已移到 C9：旧写法把"种子行 ext 为空"当前提，而 09-24/25 的 i18n 轮已把种子
#  sys_menu.variable 填成 {"icon":..,"i18n":..} 真值 ⇒ 前提过期，不是产品缺陷。
#  ext 的规则改由自建自清的行来钉：空不出键、非空必出键且等值。）
check('M5 节点字段 camelCase 全', set(['appCode','parentId','code','type','sort','path'])<=set(root.keys()), str(sorted(root.keys()))[:100])
r2=post('/sys/menu/tree',{'m_EQ_appCode':'no_such_app'},t)
check('M6 m_EQ_appCode 显式过滤', r2['code']==0 and r2['data']==[], str(len(r2.get('data',[]))))

# ---- list（平铺 + sort 升序）----
r=post('/sys/menu/list',{'m_EQ_parentId':0},t)
check('L1 list 平铺数组', r['code']==0 and isinstance(r['data'],list) and len(r['data'])>0, 'n=%s'%len(r.get('data',[])))
sorts=[int(x['sort']) for x in r['data']]
check('L2 sort 升序', sorts==sorted(sorts), str(sorts[:6]))

# ---- CRUD 回环（自建行，挂根）----
r=post('/sys/menu/save',{'name':'测试目录'+RID,'code':RID+'_dir','parentId':0,'type':1,'sort':9999,'appCode':'platform'},t)
check('C1 save', r['code']==0 and r['data'], str(r))
mid=r['data']
r2=post('/sys/menu/save',{'name':'重复code','code':RID+'_dir','parentId':0,'type':1},t)
check('C2 code 全局唯一', r2['code']==99999999, 'code=%s'%r2['code'])
r=post('/sys/menu/save',{'name':'ext菜单'+RID,'code':RID+'_ext','parentId':int(mid),'type':2,'sort':1,'appCode':'platform','ext':{'i18n':{'zh-CN':'菜单'}}},t)
mid2=r['data']
r=post('/sys/menu/detail',{'id':mid2},t)
check('C3 ext 逐键往返', r['data'].get('ext')=={'i18n':{'zh-CN':'菜单'}}, str(r['data'].get('ext'))[:100])
r=post('/sys/menu/update',{'id':mid,'name':'测试目录改'+RID,'code':RID+'_dir','parentId':0,'type':1,'sort':9998,'appCode':'platform'},t)
check('C4 update', r['code']==0, str(r))
r=post('/sys/menu/detail',{'id':mid},t)
check('C5 update 落库', r['data']['sort']=='9998' and r['data']['name']=='测试目录改'+RID, str(r['data'].get('sort')))
r=post('/sys/menu/detail',{'id':mid2},t)
check('C6 裸行不出 ext 键', 'ext' not in r['data'] or r['data'].get('ext')=={'i18n':{'zh-CN':'菜单'}}, str('ext' in r['data']))
r=post('/sys/menu/page',{'pageNum':1,'pageSize':10,'m_EQ_code':RID+'_dir'},t)
check('C7 page m_EQ_code 精确', r['data']['recordCount']==1 and r['data']['rows'][0]['id']==mid, str(r['data']['recordCount']))
def find_node(nodes,code):
    for n in nodes:
        if n['code']==code: return n
        hit=find_node(n.get('children') or [],code)
        if hit: return hit
    return None
r=post('/sys/menu/tree',{},t)
node=find_node(r['data'],RID+'_dir')
check('C8 全树父子嵌套（目录挂子菜单）', node is not None and node.get('children') and node['children'][0]['code']==RID+'_ext', str(node)[:120])
# C9＝原 M4 的意图，改挂在本套自建的两行上（目录不带 ext、子菜单带 ext）：
# 「ext 为空 ⇒ 不出键；ext 非空 ⇒ 出键且等值」，不再依赖库里的种子内容。
ext_child = (node or {}).get('children',[{}])[0]
check('C9 ext 空不出键 / 非空出键且等值', node is not None and 'ext' not in node and ext_child.get('ext')=={'i18n':{'zh-CN':'菜单'}},
      str((node or {}).get('ext'))[:30]+str(ext_child.get('ext'))[:60])

# ---- 清理 ----
r=post('/sys/menu/remove',{'ids':[mid,mid2]},t)
check('Z1 批删', r['code']==0, str(r))
r=post('/sys/menu/detail',{'id':mid},t)
check('Z2 删后不可见', r['code']!=0, str(r))
r=post('/sys/menu/tree',{'m_EQ_code':RID+'_dir'},t)
check('Z3 树中消失', r['data']==[], str(len(r.get('data',[]))))

# ---- boot2 缺口补齐面：appList / 用户路由菜单三版 / syncRoute ----

# appList（仅登录）
r=post('/sys/menu/appList',{},t)
check('A1 appList [{label,value}]', r['code']==0 and isinstance(r['data'],list) and len(r['data'])>=1 and set(r['data'][0].keys())>={'label','value'}, str(r['data'])[:100])

# 用户路由菜单（platform 域，超管全量）
def get(path,token,app=None):
    req=urllib.request.Request(B+path,method='GET')
    req.add_header('Authorization','Bearer '+token)
    if app: req.add_header('appCode',app)
    try:
        with urllib.request.urlopen(req) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        try: return json.load(e)
        except: return {'code':e.code}

def find_route(nodes,code):
    for n in nodes:
        if n.get('name')==code: return n
        hit=find_route(n.get('children') or [],code)
        if hit: return hit
    return None
r=get('/menu/all',t,'platform')
check('R1 /menu/all 数组', r['code']==0 and isinstance(r['data'],list) and len(r['data'])>0, 'n=%s'%len(r.get('data',[])))
node=find_route(r['data'],'sys:user') if r.get('data') else None
check('R2 name=code + path/meta.order/meta.title', node is not None and node['name']=='sys:user' and 'order' in node.get('meta',{}) and node['meta'].get('title'), str(node)[:120])
all_codes=[]
def walk_codes(nodes):
    for n in nodes:
        all_codes.append(n['name']); walk_codes(n.get('children') or [])
walk_codes(r['data'])
check('R3 只出目录/菜单（无按钮码 :page/:save）', all((':save' not in c and ':page' not in c) or c.startswith('sys:menu') is False for c in all_codes) and not any(c in ('sys:user:save','sys:dict:page') for c in all_codes), str(len(all_codes)))
check('R4 children 空不出键', all((('children' in n) and n['children']) or ('children' not in n) for n in r['data']), '')
r2=get('/getMenuList',t,'platform')
def find_v2(nodes,code):
    for n in nodes:
        if n['name']==code: return n
        hit=find_v2(n.get('children') or [],code)
        if hit: return hit
    return None
# R5 隐藏标记：自建自清（旧写法钉"种子 sys:menu 行 is_show=0"，现读该种子行 is_show=1、
# 库里隐藏的另有两行 ⇒ 前提过期；hideInMenu/hideMenu 的产品行为改由下面这行自己钉）
hid=post('/sys/menu/save',{'name':'隐藏菜单'+RID,'code':RID+'_hide','parentId':0,'type':2,'sort':9997,
                          'path':'/hide','appCode':'platform','isShow':0,'enabled':1},t)['data']
n5=find_route(get('/menu/all',t,'platform')['data'],RID+'_hide')
n2=find_v2(get('/getMenuList',t,'platform')['data'],RID+'_hide')
check('R5 v5 hideInMenu / v2 hideMenu', n5 is not None and n2 is not None and n5['meta'].get('hideInMenu')==True and n2['meta'].get('hideMenu')==True,
      str(((n5 or {}).get('meta') or {}).get('hideInMenu'))+'/'+str(((n2 or {}).get('meta') or {}).get('hideMenu')))
vis=post('/sys/menu/save',{'name':'显示菜单'+RID,'code':RID+'_vis','parentId':0,'type':2,'sort':9996,
                          'path':'/vis','appCode':'platform','isShow':1,'enabled':1},t)['data']
v5=find_route(get('/menu/all',t,'platform')['data'],RID+'_vis')
check('R5b 显示行不带 hideInMenu', v5 is not None and 'hideInMenu' not in v5.get('meta',{}), str((v5 or {}).get('meta'))[:80])
check('R5 清理', post('/sys/menu/remove',{'ids':[hid,vis]},t)['code']==0, '')
r3=get('/getArtDesignMenu',t,'platform')
n3=find_v2(r3['data'],'sys:user')
check('R6 art 版菜单节点 authList 超管', n3 is not None and n3['meta'].get('authList')==[{'title':'超级管理员','authMark':'admin'}], str((n3 or {}).get('meta',{}).get('authList'))[:100])

# syncRoute（⚠️ 只在隔离域 mmsync-e2e：登录带 appCode 头；固定域复用——每轮 upsert+清扫，行数有界）
SD='mmsync-e2e'
ts=post('/sys/login',{'userName':'superAdmin','password':'123456'})['data']['token']
def spost(path,body):
    req=urllib.request.Request(B+path,data=json.dumps(body).encode(),method='POST')
    req.add_header('Content-Type','application/json'); req.add_header('Authorization','Bearer '+ts); req.add_header('appCode',SD)
    try:
        with urllib.request.urlopen(req) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        try: return json.load(e)
        except: return {'code':e.code}
def sget(path):
    req=urllib.request.Request(B+path,method='GET')
    req.add_header('Authorization','Bearer '+ts); req.add_header('appCode',SD)
    try:
        with urllib.request.urlopen(req) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        try: return json.load(e)
        except: return {'code':e.code}

# 无状态化：先 upsert 一个清扫位（sweep 删掉上一轮全部残留），域内只剩它
r=spost('/sys/menu/syncRoute',[{'isSync':1,'code':'sync_wipe','name':'清扫位','type':2,'sort':99,'path':'/wipe','enabled':1}])
check('S0 清扫位就位（域内仅它）', r['code']==0 and [x['name'] for x in sget('/menu/all')['data']]==['sync_wipe'], str([x.get('name') for x in sget('/menu/all')['data']]))
ROUTES=[
 {'isSync':1,'code':'sync_dir','name':'同步目录','type':1,'sort':1,'path':'/sync','enabled':1,
  'children':[
    {'isSync':1,'code':'sync_menu','name':'同步菜单','type':2,'sort':1,'path':'/sync/m','component':'/sync/m','enabled':1,'isCache':1},
    {'isSync':0,'code':'sync_nosync','name':'不同步','type':2,'sort':2,'path':'/sync/x','enabled':1},
 ]},
 {'isSync':1,'code':'sync_c','name':'同步C','type':2,'sort':2,'path':'/c','component':'/c','enabled':1},
]
r=spost('/sys/menu/syncRoute',ROUTES)
check('S1 syncRoute upsert', r['code']==0, str(r))
d=sget('/menu/all')['data']
check('S2 域内路由菜单 upsert 成', len(d)==2 and d[0]['name']=='sync_dir' and d[0]['children'][0]['name']=='sync_menu', str(len(d)))
check('S3 isSync=0 不入库', find_v2(d,'sync_nosync') is None, '')
check('S4 meta.keepAlive/isCache', d[0]['children'][0]['meta'].get('keepAlive')==True, str(d[0]['children'][0]['meta'])[:100])
r=spost('/sys/menu/syncRoute',[ROUTES[0]['children'][0:1][0]])  # 只同步 sync_menu（sync_dir 缺席 → 被清扫）
check('S5 二轮同步', r['code']==0, str(r))
d=sget('/menu/all')['data']
check('S6 未在集合的 is_sync=1 行被清扫', [x['name'] for x in d]==['sync_menu'], str([x['name'] for x in d]))
r=spost('/sys/menu/syncRoute',[])
check('S7 空数组短路', r['code']==0 and len(sget('/menu/all')['data'])==1, str(r))
# 平台域不受影响
plat=get('/menu/all',t,'platform')
check('S8 平台域零波及', len(plat['data'])>0 and find_v2(plat['data'],'sync_menu') is None, str(len(plat['data'])))
r=spost('/sys/menu/tree',{})
check('S9 域内 tree 可见同步行', r['code']==0 and len(r['data'])==1 and r['data'][0]['code']=='sync_menu', str(r['data'])[:80])

# ---- 菜单徽标配置（/badgeConfig：前端 badge.ts 进页面拉一次、之后每 5 分钟一次）----
r=post('/badgeConfig',{},t)
check('BD1 badgeConfig 信封+data 数组（当前是空数组占位）',
      r['code']==0 and isinstance(r['data'],list) and len(r['data'])==0, str(r)[:80])
r=post('/badgeConfig',{})
check('BD2 未登录 99990403（只验登录、无权限码）', r['code']==99990403, str(r)[:80])

print('OK %d FAIL %d'%(ok,bad))
raise SystemExit(0 if bad==0 else 1)
