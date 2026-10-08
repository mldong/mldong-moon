# -*- coding: utf-8 -*-
# 通用下拉 /{module}/{table}/select + /sys/user/select + lowCode 网关矩阵（goframe 协议同构）
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

# ---- 基本形状 ----
r=post('/sys/dept/select',{},t)
check('LC1 select code0', r['code']==0 and isinstance(r['data'],list) and len(r['data'])>0, str(r)[:120])
check('LC2 item {label,value}', set(r['data'][0].keys())=={'label','value'}, str(r['data'][0]))
check('LC3 value 字符串雪花', isinstance(r['data'][0]['value'],str) and r['data'][0]['value'].isdigit(), str(r['data'][0])[:80])
r=post('/sys/dept/select',{'pageSize':1},t)
check('LC4 pageSize 截断', r['code']==0 and len(r['data'])==1)

# ---- keywords + searchKeys（多列 OR LIKE）----
r=post('/sys/dept/select',{'keywords':'一级部门','searchKeys':'name','pageSize':20},t)
check('LC5 keywords LIKE 命中', r['code']==0 and all('一级部门' in x['label'] for x in r['data']), str(r['data'])[:120])
r=post('/sys/dept/select',{'keywords':'no_such_kw_xyz','searchKeys':'name,code'},t)
check('LC6 keywords 无命中空数组', r['code']==0 and r['data']==[], str(r))
r=post('/sys/dept/select',{'keywords':'dept_10','searchKeys':'name,code'},t)
check('LC7 多列 OR 第二列命中', r['code']==0 and len(r['data'])>=1, str(r)[:120])
r=post('/sys/dept/select',{'keywords':'x','searchKeys':'no_such_col'},t)
check('LC8 searchKeys 非法列静默忽略', r['code']==0, str(r)[:120])

# ---- labelKey/valueKey 覆写 ----
r=post('/sys/dept/select',{'labelKey':'code','valueKey':'name','pageSize':2},t)
check('LC9 labelKey/valueKey 覆写', r['code']==0 and r['data'][0]['label'].startswith('dept_'), str(r['data'])[:100])
r=post('/sys/dept/select',{'labelKey':'no_such_col'},t)
check('LC10 labelKey 列不存在 9999', r['code']!=0, str(r))

# ---- extFieldNames（camel 入参 → ext 嵌套 camel 键）----
r=post('/sys/dept/select',{'extFieldNames':'parentId','pageSize':1},t)
check('LC11 ext 嵌套对象', r['code']==0 and 'ext' in r['data'][0] and 'parentId' in r['data'][0]['ext'], str(r['data'][0]))
r=post('/sys/dept/select',{'extFieldNames':'no_such_col','pageSize':1},t)
check('LC12 ext 非法列忽略', r['code']==0 and 'ext' not in r['data'][0], str(r['data'][0]))

# ---- orderBy（安全解析 + 注入免疫）----
r1=post('/sys/dept/select',{'orderBy':'id desc','pageSize':2},t)
r2=post('/sys/dept/select',{'orderBy':'id asc','pageSize':2},t)
check('LC13 orderBy desc/asc 生效', r1['code']==0 and r2['code']==0 and r1['data'][0]['value']>r2['data'][0]['value'], str(r1['data'][0])+' vs '+str(r2['data'][0]))
r=post('/sys/dept/select',{'orderBy':'id; DROP TABLE sys_dept','pageSize':2},t)
check('LC14 orderBy 注入免疫', r['code']==0, str(r)[:100])

# ---- includeType 回显 ----
r=post('/sys/dept/select',{'pageSize':1},t)
first_id=r['data'][0]['value']
r=post('/sys/dept/select',{'pageSize':2,'includeIds':[first_id,'999'],'includeType':1},t)
check('LC15 includeType=1 回显置顶', r['code']==0 and r['data'][0]['value']==first_id and not any(x['value']=='999' for x in r['data']), str(r['data'])[:120])
r=post('/sys/dept/select',{'includeIds':[first_id],'includeType':2},t)
check('LC16 includeType=2 仅 ids', r['code']==0 and len(r['data'])==1 and r['data'][0]['value']==first_id)

# ---- 通用路由 /:module/:table/select ----
r=post('/sys/dict/select',{'pageSize':2},t)
check('LC17 module+table 拼表 sys_dict', r['code']==0 and len(r['data'])>=1, str(r)[:100])
r=post('/sys/dictItem/select',{'pageSize':2},t)
check('LC18 小驼峰 table 转下划线', r['code']==0 and len(r['data'])>=1, str(r)[:100])

# ---- /sys/user/select 专属语义 ----
r=post('/sys/user/select',{'pageSize':2},t)
check('LC19 user/select 默认形状', r['code']==0 and len(r['data'])>=1 and set(r['data'][0].keys())=={'label','value'}, str(r['data'][:1]))
r=post('/sys/user/select',{'keywords':'super','pageSize':20},t)
check('LC20 user/select keywords 缺省按 labelKey(real_name)', r['code']==0 and len(r['data'])>=1, str(r)[:120])

# ---- lowCode 动态表网关 ----
r=post('/lowCode/sys_user/select',{'pageSize':2,'labelKey':'realName'},t)
check('LC21 lowCode select（sys_user 无 name 列，显式 labelKey——与 goframe 同判）', r['code']==0 and len(r['data'])>=1)
r=post('/lowCode/sys_user/page',{'pageNum':1,'pageSize':2},t)
# UC-0318：动态表行出口一律 camelCase（旧断 user_name 是 moon 自创的 snake 透出面）
check('LC22 lowCode page 形状(camelCase)', r['code']==0 and r['data']['recordCount']>=1 and isinstance(r['data']['rows'][0].get('userName'),str) and 'user_name' not in r['data']['rows'][0], str(r['data'])[:150])
r=post('/lowCode/sys_dept/detail',{'id':first_id},t)
check('LC23 lowCode detail camelCase 键(UC-0319)', r['code']==0 and r['data']['id']==first_id and 'parentId' in r['data'] and 'parent_id' not in r['data'], str(r)[:120])
r=post('/lowCode/no_such_table/select',{},t)
check('LC24 未知表 9999', r['code']!=0, str(r))
r=post('/lowCode/sys_user;drop/detail',{'id':'1'},t)
check('LC25 表名形状白名单拒绝', r['code']!=0, str(r))

# E6 防回归：datetime 列驱动是以 Blob 回来的，旧 generic_row_to_json 把 Blob 一律丢成 null
# ⇒ 低代码 page|detail 与引擎 bizData 两条出口的 create_time/update_time 全变 null。
r=post('/lowCode/sys_user/page',{'pageNum':1,'pageSize':1},t)
row=(r.get('data') or {}).get('rows') or [{}]
ct,ut=row[0].get('createTime'),row[0].get('updateTime')
check('LC26 时间列出串不出 null（Blob 分支）',
      isinstance(ct,str) and len(ct)>=19 and ct[4]=='-' and ct[10]==' ' and isinstance(ut,str) and ut[4]=='-',
      'createTime=%r updateTime=%r'%(ct,ut))

print('OK %d FAIL %d'%(ok,bad))
