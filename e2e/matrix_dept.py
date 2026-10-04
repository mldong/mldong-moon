# -*- coding: utf-8 -*-
import json,urllib.request,time
import os
B=os.environ.get('BASE','http://127.0.0.1:18680')
UN='genpost'+str(int(time.time())%100000)
def post(path,body,token=None):
    req=urllib.request.Request(B+path,data=json.dumps(body).encode(),method='POST')
    req.add_header('Content-Type','application/json')
    if token: req.add_header('Authorization','Bearer '+token)
    try:
        with urllib.request.urlopen(req) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        try: return json.load(e)
        except: return {'code':e.code}
def walk(nodes):
    for n in nodes:
        yield n
        for c in n.get('children',[]): yield from walk([c])

ok=0;bad=0
def check(name,cond,detail=''):
    global ok,bad
    if cond: ok+=1; print('PASS',name,detail)
    else: bad+=1; print('FAIL',name,detail)

t=post('/sys/login',{'userName':'superAdmin','password':'123456'})['data']['token']

# ---- post CRUD（生成物验收）----
r=post('/sys/post/save',{'name':UN,'code':UN,'sort':5},t)
pid=r['data']; check('P1 post save', r['code']==0 and pid, str(r))
r=post('/sys/post/detail',{'id':pid},t)
check('P2 post detail 回读', r['code']==0 and r['data']['name']==UN and int(r['data']['sort'])==5, str(r['data'])[:120])
r=post('/sys/post/update',{'id':pid,'name':UN+'改','code':UN,'sort':6},t)
check('P3 post update', r['code']==0)
r=post('/sys/post/detail',{'id':pid},t)
check('P4 update 回读', r['data']['name']==UN+'改' and int(r['data']['sort'])==6)
r=post('/sys/post/save',{'name':'x','code':UN},t)
check('P5 code 查重 99990003', r['code']==99990003, str(r))
r=post('/sys/post/page',{'pageNum':1,'pageSize':5,'m_EQ_code':UN},t)
check('P6 m_EQ 过滤', r['code']==0 and r['data']['recordCount']==1)
r=post('/sys/post/remove',{'ids':[pid]},t)
check('P7 post remove', r['code']==0)

# ---- dept CRUD + 树 ----
r=post('/sys/dept/save',{'name':UN+'总部','code':UN+'hq','parentId':'0'},t)
root=r['data']; check('D1 dept save root', r['code']==0 and root, str(r))
r=post('/sys/dept/save',{'name':UN+'研发','code':UN+'rd','parentId':str(root)},t)
child=r['data']; check('D2 dept save 子级', r['code']==0)
r=post('/sys/dept/save',{'name':UN+'市场','code':UN+'mkt','parentId':str(root)},t)
child2=r['data']; check('D3 dept save 兄弟', r['code']==0)
r=post('/sys/dept/detail',{'id':child},t)
check('D4 子级 parentId 回读', r['data']['parentId']==str(root), str(r['data'])[:100])
r=post('/sys/dept/save',{'name':'x','code':UN+'rd','parentId':'0'},t)
check('D5 code 查重 99990003', r['code']==99990003)
r=post('/sys/dept/list',{},t)
tree=json.dumps(r['data'],ensure_ascii=False)
check('D6 dept 树嵌套', r['code']==0 and ('"children"' in tree))
rnode=[n for n in r['data'] if n['name']==UN+'总部']
check('D7 根节点含两子', len(rnode)==1 and len(rnode[0]['children'])==2, 'children=%d'%(len(rnode[0]['children']) if rnode else -1))
r=post('/sys/dept/page',{'pageNum':1,'pageSize':10,'m_EQ_code':UN+'hq'},t)
check('D8 dept page + m_EQ', r['code']==0 and r['data']['recordCount']==1)
# ext↔variable 往返（boot2 同语义：前端提交 ext 对象 → variable JSON 串 → 返回 ext 对象）
r=post('/sys/dept/update',{'id':root,'name':UN+'总部','code':UN+'hq','parentId':'0','ext':{'i18nKey':'dept.hq','level':3,'tags':['a','b']}},t)
check('D8b update 带 ext 对象', r['code']==0, str(r))
r=post('/sys/dept/detail',{'id':root},t)
ext=r['data'].get('ext')
check('D8c detail 回 ext 对象', isinstance(ext,dict) and ext.get('i18nKey')=='dept.hq' and ext.get('level')==3 and ext.get('tags')==['a','b'], str(ext))
# 清空 ext → null
r=post('/sys/dept/update',{'id':root,'name':UN+'总部','code':UN+'hq','parentId':'0'},t)
r=post('/sys/dept/detail',{'id':root},t)
check('D8d 不带 ext 回空对象（boot2 空 Dict 语义）', r['data'].get('ext')=={}, str(r['data'].get('ext')))
# 部门用户树：把 u0011 挂到 child 部门下
import urllib.request as _u
# 建自有用户挂子部门（不碰种子数据；跨套件残留依赖已两次假红，教训入册）
r=post('/sys/user/save',{'userName':UN+'du','realName':'树验证','deptId':str(child),'mobilePhone':'13899990002'},t)
duid=r['data']; check('D9 建用户挂子部门', r['code']==0 and duid, str(r))
r=post('/sys/user/getDeptUserTree',{},t)
rnode2=[n for n in walk(r['data']) if n.get('nodeType')=='1' and n['value']==str(child)]
check('D10 部门用户树含部门节点+用户叶', r['code']==0 and len(rnode2)==1 and any(x['nodeType']=='2' and x['label']=='树验证' for x in rnode2[0]['children']))
r=post('/sys/dept/remove',{'ids':[root,child,child2]},t)
check('D11 dept remove 批量', r['code']==0)
# join 核验：自建部门+自建用户，按 userName 精确定位（不依赖全局分页序）
r=post('/sys/dept/save',{'name':UN+'d12','code':UN+'d12','parentId':'0'},t)
d12=r['data']
r=post('/sys/user/save',{'userName':UN+'u12','realName':'join验证','deptId':str(d12),'mobilePhone':'13899990001'},t)
u12=r['data']
r=post('/sys/user/page',{'pageNum':1,'pageSize':5,'m_EQ_userName':UN+'u12'},t)
check('D12 用户页 join deptName', r['code']==0 and len(r['data']['rows'])==1 and r['data']['rows'][0]['deptName']==UN+'d12', str(r['data']['rows'])[:120])
post('/sys/user/remove',{'ids':[u12]},t)
post('/sys/dept/remove',{'ids':[d12]},t)

print('OK %d FAIL %d'%(ok,bad))
