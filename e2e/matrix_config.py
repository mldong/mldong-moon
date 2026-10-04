# -*- coding: utf-8 -*-
import json,urllib.request,time
import os
B=os.environ.get('BASE','http://127.0.0.1:18680')
GC='gencfg'+str(int(time.time())%100000)
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
# CRUD（生成物验收）
r=post('/sys/config/save',{'name':'版权','code':'PUBLIC_'+GC+'_COPYRIGHT','groupCode':GC,'content':'(c) mldong','isSys':0},t)
cid=r['data']; check('C1 save', r['code']==0 and cid, str(r))
r=post('/sys/config/save',{'name':'内部项','code':GC+'_INTERNAL','groupCode':GC,'content':'secret'},t)
cid2=r['data']; check('C2 save 内部项', r['code']==0)
r=post('/sys/config/detail',{'id':cid},t)
check('C3 detail 回读', r['code']==0 and r['data']['code']=='PUBLIC_'+GC+'_COPYRIGHT' and r['data']['content']=='(c) mldong' and r['data']['groupCode']==GC, str(r['data'])[:140])
r=post('/sys/config/save',{'name':'x','code':'PUBLIC_'+GC+'_COPYRIGHT','groupCode':GC},t)
check('C4 code 查重 99990003', r['code']==99990003)
r=post('/sys/config/update',{'id':cid,'name':'版权改','code':'PUBLIC_'+GC+'_COPYRIGHT','groupCode':GC,'content':'(c) mldong 2026'},t)
check('C5 update', r['code']==0)
r=post('/sys/config/detail',{'id':cid},t)
check('C6 update 回读', r['data']['content']=='(c) mldong 2026')
r=post('/sys/config/page',{'pageNum':1,'pageSize':10,'m_EQ_groupCode':GC},t)
check('C7 page m_EQ_groupCode', r['code']==0 and r['data']['recordCount']==2)
# public（免鉴权 + PUBLIC 前缀 + enabled 过滤）
r=post('/sys/config/public',{})
check('C8 public 免鉴权有数据', r['code']==0 and isinstance(r['data'],dict) and r['data'].get('PUBLIC_'+GC+'_COPYRIGHT')=='(c) mldong 2026', str(r['data'])[:160])
check('C9 非 PUBLIC 不入', GC+'_INTERNAL' not in (r['data'] or {}))
r=post('/sys/config/update',{'id':cid,'name':'版权改','code':'PUBLIC_'+GC+'_COPYRIGHT','groupCode':GC,'content':'(c) mldong 2026','enabled':0},t)
r2=post('/sys/config/public',{})
check('C10 disabled 不入', r2['data'].get(GC+'_PUBLIC_COPYRIGHT') is None)
post('/sys/config/update',{'id':cid,'name':'版权改','code':'PUBLIC_'+GC+'_COPYRIGHT','groupCode':GC,'content':'(c) mldong 2026','enabled':1},t)
# 守卫面：受保护端点无 token 401
r=post('/sys/config/page',{'pageNum':1,'pageSize':1})
check('C11 page 无 token 99990403', r['code']==99990403)
# 清理
r=post('/sys/config/remove',{'ids':[cid,cid2]},t)
check('C12 remove 批量', r['code']==0)
r=post('/sys/config/public',{})
check('C13 删除后 public 不含', (r['data'] or {}).get(GC+'_PUBLIC_COPYRIGHT') is None)
print('OK %d FAIL %d'%(ok,bad))
