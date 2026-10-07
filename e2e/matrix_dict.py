# -*- coding: utf-8 -*-
# 字典模块矩阵（sys_dict + sys_dict_item）——自建自清（dt 前缀 + m_EQ_code 圈定 + finally remove）
# 覆盖：CRUD 五端点 / code 全局唯一 / getByDictType 正负 + dataType coerce + enabled 过滤
#       enumDictList/customDictList 清单契约 / ext 四态（UC-0426 双读侧）/ dictItem CRUD
#       dict 内 code 唯一 / dictId 不存在 / m_ 操作符抽测 / keywords / orderBy / 漏传过滤全量
import json,urllib.request,time
import os
B=os.environ.get('BASE','http://127.0.0.1:18680')
RID='dt'+str(int(time.time())%1000000)

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

def find_dict(code):
    r=post('/sys/dict/page',{'pageNum':1,'pageSize':10,'m_EQ_code':code},t)
    rows=r['data']['rows']
    return rows[0] if len(rows)==1 else None

# ---- dict CRUD（生成面验收）----
r=post('/sys/dict/save',{'name':'契约字典'+RID,'code':RID+'_d1','groupCode':'default','dataType':1,'enabled':1,'sort':1,'remark':'matrix'},t)
check('DC1 dict save', r['code']==0 and r['data'], str(r))
d1=r['data']
r2=post('/sys/dict/save',{'name':'重复code','code':RID+'_d1','groupCode':'default'},t)
check('DC2 dict code 全局唯一', r2['code']==99999999, 'code=%s'%r2['code'])
r=post('/sys/dict/detail',{'id':d1},t)
check('DC3 detail 回读', r['code']==0 and r['data']['code']==RID+'_d1' and r['data']['dataType']==1, str(r.get('data',{}).get('code')))
r=post('/sys/dict/update',{'id':d1,'name':'契约字典改'+RID,'code':RID+'_d1','groupCode':'default','dataType':1,'enabled':1,'sort':9},t)
check('DC4 update', r['code']==0, str(r))
r=post('/sys/dict/detail',{'id':d1},t)
check('DC5 update 落库（sort/name）', r['data']['sort']=='9' and r['data']['name']=='契约字典改'+RID, str(r['data'].get('sort')))

# ---- getByDictType ----
# dictId 19 位雪花超 JS 安全整数走字符串（DI1），数字直传压各栈雪花精度解析（DI2，UC-0430 同款）
ri=post('/sys/dictItem/save',{'dictId':d1,'name':'甲','code':RID+'_a','sort':1,'enabled':1},t)
check('DI1 item save（dictId 字符串）', ri['code']==0 and ri['data'], str(ri))
ia=ri['data']
ri=post('/sys/dictItem/save',{'dictId':int(d1),'name':'乙','code':RID+'_b','sort':2,'enabled':1},t)
check('DI2 item save（dictId 数字直传）', ri['code']==0, str(ri))
ib=ri['data']
ri=post('/sys/dictItem/save',{'dictId':int(d1),'name':'丙','code':RID+'_c','sort':3,'enabled':0},t)
ic=ri['data']
r=post('/sys/dict/getByDictType',{'dictType':RID+'_d1'},t)
check('G1 getByDictType 直返数组', r['code']==0 and isinstance(r['data'],list) and len(r['data'])==2, str(r))
check('G2 enabled=0 不出', all(it['value']!=RID+'_c' for it in r['data']), str(r['data']))
check('G3 出口 label/value 键', set(r['data'][0].keys())=={'label','value'}, str(sorted(r['data'][0].keys())))
check('G4 dataType=1 值为串', all(isinstance(it['value'],str) for it in r['data']), str(r['data']))
r=post('/sys/dict/getByDictType',{'dictType':'e2e_unknown'},t)
check('G5 未知类型空数组', r['code']==0 and r['data']==[], str(r))

# dataType=2 数值 coerce
r=post('/sys/dict/save',{'name':'数值字典'+RID,'code':RID+'_n','groupCode':'default','dataType':2,'enabled':1,'sort':2},t)
dn=r['data']
post('/sys/dictItem/save',{'dictId':int(dn),'name':'启用','code':'1','sort':1,'enabled':1},t)
post('/sys/dictItem/save',{'dictId':int(dn),'name':'停用','code':'0','sort':2,'enabled':1},t)
r=post('/sys/dict/getByDictType',{'dictType':RID+'_n'},t)
check('G6 dataType=2 值为数值', all(isinstance(it['value'],int) for it in r['data']), str(r['data']))

# ---- enumDictList / customDictList（UC-0431/0432 基础仓格）----
r=post('/sys/dict/enumDictList',{},t)
check('L1 enumDictList 非空', r['code']==0 and isinstance(r['data'],list) and len(r['data'])>=1, str(len(r.get('data',[]))))
check('L2 每项 dataType 整型 1|2', all(isinstance(d.get('dataType'),int) and not isinstance(d.get('dataType'),bool) and d['dataType'] in (1,2) for d in r['data']), str(r['data'])[:120])
enum_keys={d['dictKey']:d for d in r['data']}
BOOT2_ENUMS=['yes_no','sex','sys_user_admin_type','sys_role_role_type','sys_role_data_scope','sys_menu_type','sys_menu_open_type','sys_menu_app_code','sys_dict_data_type','sys_message_msg_type','sys_op_log_op_type','sys_vis_log_vis_type','sys_sms_biz_type','sys_sms_log_status','sys_timer_state','sys_third_party_callback_handle_status','sys_task_execution_queue_state','sys_task_execution_history_state']
check('L2b boot2 sys 域枚举全在册(18)', all(k in enum_keys for k in BOOT2_ENUMS), str([k for k in BOOT2_ENUMS if k not in enum_keys]))
check('L2c yes_no 码表 1是/0否', [it['dictItemValue'] for it in enum_keys['yes_no']['items']]==[1,0], str(enum_keys.get('yes_no',{}).get('items')))
check('L2d menu_type 四项 1-4', [it['dictItemValue'] for it in enum_keys['sys_menu_type']['items']]==[1,2,3,4], str(enum_keys.get('sys_menu_type',{}).get('items')))
check('L2e sms_biz 码表 10-60', [it['dictItemValue'] for it in enum_keys['sys_sms_biz_type']['items']]==[10,20,30,40,50,60], str(enum_keys.get('sys_sms_biz_type',{}).get('items')))
r=post('/sys/dict/getByDictType',{'dictType':'sys_role_data_scope'},t)
check('L2f 枚举路径 getByDictType 可解析(数据范围5项)', r['code']==0 and [it['value'] for it in r['data']]==[1,2,3,4,5], str(r['data'])[:120])
r2=post('/sys/dict/customDictList',{},t)
check('L3 customDictList 数组（基础仓允许空）', r2['code']==0 and isinstance(r2['data'],list), str(r2))
custom_keys=set(d.get('dictKey') for d in r2['data']) if r2['data'] else set()
dp=post('/sys/dict/page',{'pageNum':1,'pageSize':100},t)
db_codes=set(row['code'] for row in dp['data']['rows'])
check('L4 两域分离（custom ∩ db = ∅）', not (custom_keys & db_codes), str(custom_keys & db_codes))
by=post('/sys/dict/getByDictType',{'dictType':'yes_no'},t)
check('L5 枚举注册表 getByDictType 可解析', by['code']==0 and len(by['data'])==2 and by['data'][0]['value']==1, str(by['data']))

# ---- ext 四态（UC-0426 双读侧）----
EXT={'i18n':{'zh-CN':'中文','en-US':'en'},'search':1}
r=post('/sys/dict/save',{'name':'ext字典'+RID,'code':RID+'_e','groupCode':'default','dataType':1,'enabled':1,'sort':3,'ext':EXT},t)
de=r['data']
row=find_dict(RID+'_e')
check('E1 page 行 ext 逐键往返', row is not None and row.get('ext')==EXT, str(row and row.get('ext'))[:120])
r=post('/sys/dict/detail',{'id':de},t)
check('E2 detail ext 逐键往返', r['data'].get('ext')==EXT, str(r['data'].get('ext'))[:120])
NEW={'i18n':{'zh-CN':'中文改'}}
r=post('/sys/dict/update',{'id':de,'name':'ext字典'+RID,'code':RID+'_e','groupCode':'default','dataType':1,'enabled':1,'sort':3,'ext':NEW},t)
r=post('/sys/dict/detail',{'id':de},t)
check('E3 update ext 整体覆盖', r['data'].get('ext')==NEW and 'search' not in (r['data'].get('ext') or {}), str(r['data'].get('ext'))[:120])
r=post('/sys/dict/save',{'name':'裸字典'+RID,'code':RID+'_bare','groupCode':'default','dataType':1,'enabled':1,'sort':4},t)
dbare=r['data']
row=find_dict(RID+'_bare')
check('E4 不带 ext page 不出键', row is not None and 'ext' not in row, str('ext' in (row or {})))
r=post('/sys/dict/detail',{'id':dbare},t)
check('E5 不带 ext detail 不出键', 'ext' not in r['data'], str('ext' in r['data']))
r=post('/sys/dict/update',{'id':dbare,'name':'裸字典'+RID,'code':RID+'_bare','groupCode':'default','dataType':1,'enabled':1,'sort':4,'ext':{}},t)
r=post('/sys/dict/detail',{'id':dbare},t)
check('E6 update ext={} 不出键', 'ext' not in r['data'], str('ext' in r['data']))

# ---- dictItem 唯一性 / 负向 ----
r=post('/sys/dictItem/save',{'dictId':int(d1),'name':'重码','code':RID+'_a','sort':5,'enabled':1},t)
check('N1 dict 内 code 唯一', r['code']==99999999, 'code=%s'%r['code'])
r=post('/sys/dictItem/save',{'dictId':'999999999999999999','name':'孤儿','code':RID+'_x','sort':1,'enabled':1},t)
check('N2 dictId 不存在拒', r['code']!=0, str(r))

# ---- dictItem page：m_ / keywords / orderBy / 漏传全量 ----
def gpage(extra):
    body={'pageNum':1,'pageSize':50}; body.update(extra)
    r=post('/sys/dictItem/page',body,t)
    return r['data']['rows'], r['data']['recordCount']
rows,total=gpage({'m_EQ_dictId':int(d1)})
check('Q1 m_EQ_dictId 圈定', total==3 and all(str(x['dictId'])==d1 for x in rows), 'total=%s'%total)
rows,total=gpage({'m_EQ_dictId':int(d1),'m_EQ_sort':2})
check('Q2 m_EQ_sort', [str(x['code']) for x in rows]==[RID+'_b'], str(rows))
rows,total=gpage({'m_EQ_dictId':int(d1),'m_GE_sort':2})
check('Q3 m_GE_sort', total==2, 'total=%s'%total)
rows,total=gpage({'m_EQ_dictId':int(d1),'m_LIKE_name':'乙'})
check('Q4 m_LIKE_name', [str(x['code']) for x in rows]==[RID+'_b'], str(rows))
rows,total=gpage({'m_EQ_dictId':int(d1),'m_BT_sort':[1,2]})
check('Q5 m_BT 数组', total==2, 'total=%s'%total)
rows,total=gpage({'m_EQ_dictId':int(d1),'m_IN_sort':'2,3'})
check('Q6 m_IN csv', total==2, 'total=%s'%total)
rows,total=gpage({'m_EQ_dictId':int(d1),'m_FOO_sort':1})
check('Q7 非法操作符静默忽略', total==3, 'total=%s'%total)
rows,total=gpage({'m_EQ_dictId':int(d1),'keywords':'乙','searchKeys':'name'})
check('Q8 keywords+searchKeys', [str(x['code']) for x in rows]==[RID+'_b'], str(rows))
rows,_=gpage({'m_EQ_dictId':int(d1),'orderBy':'sort desc'})
check('Q9 orderBy sort desc 全序', [str(x['code']) for x in rows]==[RID+'_c',RID+'_b',RID+'_a'], str([str(x['code']) for x in rows]))
rows,total=gpage({'m_EQ_dictId':int(d1),'orderBy':'sort;drop table sys_dict'})
check('Q10 orderBy 白名单负向静默', total==3, 'total=%s'%total)
_,total_all=gpage({})
check('Q11 漏传过滤=全量', total_all>=3, 'total=%s'%total_all)

# ---- 清理（自建自清）----
ids=[de,dbare,dn]
r=post('/sys/dict/remove',{'ids':[d1,de,dbare,dn]},t)
check('Z1 dict 批删', r['code']==0, str(r))
r=post('/sys/dictItem/remove',{'ids':[ia,ib,ic]},t)
check('Z2 item 批删', r['code']==0, str(r))
r=post('/sys/dict/detail',{'id':de},t)
check('Z3 删后 detail 404 语义', r['code']!=0, str(r))

print('OK %d FAIL %d'%(ok,bad))
raise SystemExit(0 if bad==0 else 1)
