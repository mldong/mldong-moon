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
check('M4 种子行 ext 空不出键', all('ext' not in node for node in r['data']), str([k for node in r['data'][:3] for k in node.keys() if k=='ext']))
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
check('C2 code 全局唯一', r2['code']==99990003, 'code=%s'%r2['code'])
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

# ---- 清理 ----
r=post('/sys/menu/remove',{'ids':[mid,mid2]},t)
check('Z1 批删', r['code']==0, str(r))
r=post('/sys/menu/detail',{'id':mid},t)
check('Z2 删后不可见', r['code']!=0, str(r))
r=post('/sys/menu/tree',{'m_EQ_code':RID+'_dir'},t)
check('Z3 树中消失', r['data']==[], str(len(r.get('data',[]))))

print('OK %d FAIL %d'%(ok,bad))
raise SystemExit(0 if bad==0 else 1)
