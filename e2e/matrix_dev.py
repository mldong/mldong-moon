# -*- coding: utf-8 -*-
# dev 元数据端点矩阵（5 例）—— dbTable/column/list/守卫/边界
import json,urllib.request,os
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
t=post('/sys/login',{'userName':'superAdmin','password':'123456'})['data']['token']
ok=0
r=post('/dev/schema/dbTable',{'keywords':'sys_user'},t)
c=(r['code']==0 and len(r['data'])>=1); ok+= 1 if c else 0; print('PASS' if c else 'FAIL','D1 dbTable keywords',str(r)[:100])
r=post('/dev/schema/column/list',{'tableName':'sys_user'},t)
c=(r['code']==0 and len(r['data'])==21); ok+= 1 if c else 0; print('PASS' if c else 'FAIL','D2 column/list 21')
r=post('/dev/schema/dbTable',{},'garbage')
c=(r['code']==99990401); ok+= 1 if c else 0; print('PASS' if c else 'FAIL','D3 未登录 401')
r=post('/dev/schema/dbTable',{},t)
c=(r['code']==0 and len(r['data'])>10); ok+= 1 if c else 0; print('PASS' if c else 'FAIL','D4 全表')
r=post('/dev/schema/column/list',{'tableName':'no_such_table_xyz'},t)
c=(r['code']==0 and len(r['data'])==0); ok+= 1 if c else 0; print('PASS' if c else 'FAIL','D5 不存在表空列')
print('OK %d FAIL %d'%(ok,5-ok))
