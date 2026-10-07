# -*- coding: utf-8 -*-
# dev 模块矩阵（~55 例）——三台账 CRUD + 特殊端点（dbTable/importTable/getByTableName/
# updateDesigner/updateSort/keys）+ 自愈开关闭环；boot2 22 端点黑盒
import json,urllib.request,os
B=os.environ.get('BASE','http://127.0.0.1:18680')
def req(path,body=None,token=None,method='POST',headers=None):
    data=json.dumps(body).encode() if body is not None and method=='POST' else (b'{}' if method=='POST' else None)
    r=urllib.request.Request(B+path,data=data,method=method)
    r.add_header('Content-Type','application/json')
    if token: r.add_header('Authorization','Bearer '+token)
    for k,v in (headers or {}).items(): r.add_header(k,v)
    try:
        with urllib.request.urlopen(r) as resp: return json.load(resp)
    except urllib.error.HTTPError as e:
        try: return json.load(e)
        except: return {'code':e.code}
def post(path,body,token=None,headers=None): return req(path,body,token,'POST',headers)
def get(path,token=None,headers=None): return req(path,None,token,'GET',headers)
ok=0;bad=0
def check(name,cond,detail=''):
    global ok,bad
    if cond: ok+=1; print('PASS',name,detail)
    else: bad+=1; print('FAIL',name,detail)

t=post('/sys/login',{'userName':'superAdmin','password':'123456'})['data']['token']
GC='mdev'+os.urandom(3).hex()  # 本轮自建资源前缀（自清理）
created={'schema':[],'field':[],'group':[]}
def cleanup():
    for fid in created['field']:
        post('/dev/schemaField/remove',{'ids':[fid]},t)
    for sid in created['schema']:
        post('/dev/schema/remove',{'ids':[sid]},t)
    for gid in created['group']:
        post('/dev/schemaGroup/remove',{'ids':[gid]},t)

# ── A. runner 契约口径（UC-0303/0306/0310 黑盒复刻）──
r=post('/dev/schema/page',{'pageNum':1,'pageSize':5},t)
check('A1 page 五键+rows 非空', r['code']==0 and all(k in r['data'] for k in ('pageNum','pageSize','recordCount','totalPage','rows')) and len(r['data']['rows'])>=1, str(r)[:80])
row0=r['data']['rows'][0]
check('A2 rows[0] id 字符串+tableName+ext+variable', isinstance(row0['id'],str) and all(k in row0 for k in ('tableName','ext','variable')), str(row0)[:120])
r=get('/dev/schema/getByTableName?tableName='+row0['tableName'],t)
check('A3 getByTableName 四键+columns 非空', r['code']==0 and all(k in r['data'] for k in ('id','tableName','columns','ext')) and len(r['data']['columns'])>=1, str(r)[:80])
c0=r['data']['columns'][0]
check('A4 columns[0] 六键+id 字符串', isinstance(c0['id'],str) and all(k in c0 for k in ('schemaId','fieldName','component','sort','ext')), str(c0)[:120])

# ── B. getByTableName 鉴权四态 ──
r=get('/dev/schema/getByTableName?tableName=sys_user')
check('B1 无 token 99990403', r['code']==99990403, str(r)[:80])
r=get('/dev/schema/getByTableName?tableName=sys_user',t)
check('B2 token 放行', r['code']==0 and r['data']['tableName']=='sys_user')
r=get('/dev/schema/getByTableName?tableName=sys_user',headers={'appId':'wrong','appSecret':'nope'})
check('B3 错凭证 99990403', r['code']==99990403, str(r)[:80])
r=get('/dev/schema/getByTableName?tableName=sys_user',headers={'appId':'admin','appSecret':'123456'})
check('B4 对凭证免登录放行', r['code']==0 and r['data']['tableName']=='sys_user', str(r)[:80])

# ── C. 种子模型 VO 派生 ──
r=get('/dev/schema/getByTableName?tableName=sys_user',t)
d=r['data']
check('C1 派生三件 moduleName/tableCamelName/className', d.get('moduleName')=='sys' and d.get('tableCamelName')=='user' and d.get('className')=='User', str({k:d.get(k) for k in ('moduleName','tableCamelName','className')}))
check('C2 schemaGroup 聚合存在', isinstance(d.get('schemaGroup'),dict) and d['schemaGroup'].get('code')=='sys', str(d.get('schemaGroup'))[:100])
byname={c['fieldName']:c for c in d['columns']}
check('C3 字段驼峰+listSort', byname['user_name']['fieldCamelName']=='userName' and byname['user_name']['listSort']>=0, str(byname.get('user_name'))[:140])
check('C4 主键隐藏 ext', byname['id']['ext'].get('listHide')==1 and byname['id']['ext'].get('Input_type')=='hidden', str(byname['id']['ext'])[:100])
r=get('/dev/schema/getByTableName?tableName='+str(d['id']),t)
check('C5 数字 id 兼容解析', r['code']==0 and r['data']['tableName']=='sys_user', str(r)[:80])
r=post('/dev/schema/detail',{'id':'sys_user'},t)
check('C6 detail id 实当 tableName 用', r['code']==0 and r['data']['tableName']=='sys_user', str(r)[:80])

# ── D. dbTable disabled 标记 ──
r=post('/dev/schema/dbTable',{'keywords':'sys_user'},t)
check('D1 dbTable disabled=true(已导入)', r['code']==0 and r['data'][0]['disabled'] is True, str(r['data'][:1]))
r=post('/dev/schema/dbTable',{'keywords':'devtest_import_probe'},t)
probe_before=r['code']==0 and len(r['data'])==1 and r['data'][0]['disabled'] is False
check('D2 dbTable 探针表 disabled=false', probe_before, str(r['data'][:1]))

# ── E. schemaGroup CRUD + code 唯一 ──
r=post('/dev/schemaGroup/save',{'name':'矩阵分组','code':GC,'sort':1},t)
gid=r['data']; created['group'].append(int(gid))
check('E1 group save', r['code']==0 and gid, str(r))
r=post('/dev/schemaGroup/save',{'name':'重复','code':GC},t)
check('E2 group code 唯一 99999999', r['code']==99999999, str(r)[:80])
r=post('/dev/schemaGroup/page',{'pageNum':1,'pageSize':5,'m_EQ_code':GC},t)
check('E3 group page m_EQ', r['code']==0 and r['data']['recordCount']==1 and r['data']['rows'][0]['name']=='矩阵分组', str(r['data'])[:80])
r=post('/dev/schemaGroup/update',{'id':gid,'name':'矩阵分组改','code':GC},t)
check('E4 group update', r['code']==0)
r=post('/dev/schemaGroup/detail',{'id':gid},t)
check('E5 group detail 回读', r['code']==0 and r['data']['name']=='矩阵分组改')

# ── F. schema CRUD + keys 直更 + updateDesigner ──
r=post('/dev/schema/save',{'tableName':'mdev_probe','remark':'矩阵模型','schemaGroupId':int(gid),'ext':{'mflag':GC}},t)
sid=int(r['data']); created['schema'].append(sid)
check('F1 schema save + id 串', r['code']==0 and isinstance(r['data'],str), str(r))
r=post('/dev/schema/detail',{'id':sid},t)
check('F2 schema detail ext 往返', r['code']==0 and r['data']['ext'].get('mflag')==GC, str(r['data'].get('ext')))
r=post('/dev/schema/update',{'id':sid,'tableName':'mdev_probe','remark':'矩阵模型改','schemaGroupId':int(gid)},t)
check('F3 schema update', r['code']==0)
r=post('/dev/schema/updateListKeys',{'id':sid,'listKeys':'col_a,col_b'},t)
check('F4 updateListKeys', r['code']==0)
r=post('/dev/schema/updateSearchFormKeys',{'id':sid,'searchFormKeys':'col_a'},t)
check('F5 updateSearchFormKeys', r['code']==0)
r=post('/dev/schema/detail',{'id':sid},t)
check('F6 keys 回读', r['data']['listKeys']=='col_a,col_b' and r['data']['searchFormKeys']=='col_a', str({k:r['data'].get(k) for k in ('listKeys','searchFormKeys')}))
# updateDesigner：columns 全删重插，sort 从 100 起
cols=[{'fieldName':'col_a','remark':'列A','dataType':'17','component':'Input'},
      {'fieldName':'col_b','remark':'列B','dataType':'13','component':'InputNumber'}]
r=post('/dev/schema/updateDesigner',{'id':sid,'tableName':'mdev_probe','remark':'矩阵模型改','columns':cols},t)
d=r['data']
check('F7 updateDesigner 返回 VO', r['code']==0 and d.get('tableName')=='mdev_probe' and len(d.get('columns',[]))==2, str(d)[:100])
if d.get('columns'):
    check('F8 designer 列 sort=100,101', str(d['columns'][0]['sort'])=='100' and str(d['columns'][1]['sort'])=='101', str([(c['fieldName'],c['sort']) for c in d['columns']]))
    for c in d['columns']: created['field'].append(int(c['id']))

# ── G. schemaField CRUD + 物理删 + updateSort ──
r=post('/dev/schemaField/save',{'schemaId':sid,'fieldName':'col_c','remark':'列C','dataType':'17','component':'Input','sort':102},t)
fid_c=int(r['data']); created['field'].append(fid_c)
check('G1 field save', r['code']==0 and fid_c, str(r))
r=post('/dev/schemaField/page',{'pageNum':1,'pageSize':10,'m_EQ_schemaId':sid},t)
check('G2 field page 默认 sort 升序', r['code']==0 and [x['fieldName'] for x in r['data']['rows']]==['col_a','col_b','col_c'], str([x['fieldName'] for x in r['data']['rows']]))
r=post('/dev/schemaField/detail',{'id':fid_c},t)
check('G3 field detail', r['code']==0 and r['data']['fieldName']=='col_c')
r=post('/dev/schemaField/update',{'id':fid_c,'schemaId':sid,'fieldName':'col_c','remark':'列C改','dataType':'17','component':'Textarea'},t)
check('G4 field update', r['code']==0)
# updateSort：拖 col_c(index2) → col_a(index0)：boot2 算法 col_c=0、col_a=1、col_b=-1
r=post('/dev/schemaField/updateSort',{'schemaId':sid,'dragRowId':fid_c,'hoverRowId':int(d['columns'][0]['id'])},t)
check('G5 updateSort 受理', r['code']==0, str(r))
r=post('/dev/schemaField/page',{'pageNum':1,'pageSize':10,'m_EQ_schemaId':sid},t)
sorts={x['fieldName']:x['sort'] for x in r['data']['rows']}
check('G6 updateSort 算法落点', str(sorts.get('col_c'))=='100' and str(sorts.get('col_a'))=='101' and str(sorts.get('col_b'))=='102', str(sorts))
r=post('/dev/schemaField/remove',{'ids':[fid_c]},t)
r2=post('/dev/schemaField/page',{'pageNum':1,'pageSize':10,'m_EQ_schemaId':sid},t)
check('G7 field remove 物理删', r['code']==0 and r2['data']['recordCount']==2, str(r2['data']['recordCount']))
if fid_c in created['field']: created['field'].remove(fid_c)

# ── H. importTable 探针（分组前缀匹配 + 推断器 + 先删重建幂等）──
r=post('/dev/schema/importTable',{'tableNames':['devtest_import_probe']},t)
check('H1 importTable 受理', r['code']==0, str(r))
r=get('/dev/schema/getByTableName?tableName=devtest_import_probe',t)
if r['code']!=0:
    check('H2 import 后可查', False, str(r)[:100]); d=None
else:
    d=r['data']; created['schema'].append(int(d['id']))
    check('H2 import 后可查', True)
if d:
    check('H3 分组前缀匹配 devtest', (d.get('schemaGroup') or {}).get('code')=='devtest', str(d.get('schemaGroup'))[:80])
    byname={c['fieldName']:c for c in d['columns']}
    check('H4 字段数 6（is_deleted 过滤）', len(d['columns'])==6, str(len(d['columns'])))
    comp={k:v['component'] for k,v in byname.items()}
    check('H5 推断组件四支', comp.get('probe_name')=='Input' and comp.get('probe_status')=='ApiDict' and comp.get('probe_remark')=='Textarea' and comp.get('dict_id')=='ApiSelect' and comp.get('probe_time')=='DatePicker', str(comp))
    dt={k:v['dataType'] for k,v in byname.items()}
    check('H6 data_type 枚举 code', dt.get('id')=='13' and dt.get('probe_status')=='16' and dt.get('probe_remark')=='22' and dt.get('probe_time')=='27', str(dt))
    check('H7 ApiSelect 关联 api', byname['dict_id']['ext'].get('ApiSelect_api')=='/sys/dict/select', str(byname['dict_id']['ext'])[:90])
    check('H8 Boolean 字典 yes_no', byname['probe_status']['ext'].get('ApiDict_code')=='yes_no', str(byname['probe_status']['ext'])[:90])
    first_ids=[c['id'] for c in d['columns']]
    r=post('/dev/schema/importTable',{'tableNames':['devtest_import_probe']},t)
    r2=get('/dev/schema/getByTableName?tableName=devtest_import_probe',t)
    d2=r2['data']; created['schema'].append(int(d2['id']))
    check('H9 重复导入先删重建幂等', r['code']==0 and len(d2['columns'])==6 and [c['id'] for c in d2['columns']]!=first_ids, 'ids changed')
r=post('/dev/schema/dbTable',{'keywords':'devtest_import_probe'},t)
check('H10 导入后 disabled=true', r['code']==0 and r['data'][0]['disabled'] is True, str(r['data'][:1]))

# ── I. getByTableName 自愈闭环（sys_config 开关 DEFAULT_SCHEMA_AUTO_IMPORT）──
cfg=post('/sys/config/page',{'pageNum':1,'pageSize':5,'m_EQ_code':'DEFAULT_SCHEMA_AUTO_IMPORT'},t)
cfg_id=None
if cfg['code']==0 and cfg['data']['recordCount']==1: cfg_id=cfg['data']['rows'][0]['id']
r=get('/dev/schema/getByTableName?tableName=sys_post',headers={'appId':'admin','appSecret':'123456'})
check('I1 自愈关：未知模型 99990002', r['code']==99990002, str(r)[:80])
# 翻开关（sys_config upsert）
if cfg_id is None:
    r=post('/sys/config/save',{'name':'schema自愈导入','code':'DEFAULT_SCHEMA_AUTO_IMPORT','groupCode':'dev','content':'true','isSys':0},t)
    check('I2 建 config 开关', r['code']==0, str(r)[:80])
else:
    r=post('/sys/config/update',{'id':cfg_id,'name':'schema自愈导入','code':'DEFAULT_SCHEMA_AUTO_IMPORT','groupCode':'dev','content':'true','isSys':0},t)
    check('I2 翻 config 开关', r['code']==0, str(r)[:80])
r=get('/dev/schema/getByTableName?tableName=sys_post',headers={'appId':'admin','appSecret':'123456'})
healed=r['code']==0 and r['data'].get('tableName')=='sys_post'
check('I3 自愈落库后可查', healed, str(r)[:100])
if healed:
    created['schema'].append(int(r['data']['id']))
    check('I4 自愈模型字段非空', len(r['data']['columns'])>=5, str(len(r['data'].get('columns',[]))))
# 回关（留 config 行，内容回 false——boot2 默认 false 口径）
if cfg_id is None:
    cfg=post('/sys/config/page',{'pageNum':1,'pageSize':5,'m_EQ_code':'DEFAULT_SCHEMA_AUTO_IMPORT'},t)
    cfg_id=cfg['data']['rows'][0]['id'] if cfg['data']['recordCount']==1 else None
if cfg_id:
    post('/sys/config/update',{'id':cfg_id,'name':'schema自愈导入','code':'DEFAULT_SCHEMA_AUTO_IMPORT','groupCode':'dev','content':'false','isSys':0},t)
r=get('/dev/schema/getByTableName?tableName=sys_menu',headers={'appId':'admin','appSecret':'123456'})
check('I5 回关后不自愈', r['code']==99990002, str(r)[:80])

# ── 清理（自建域自清；自愈模型/探针模型一并）──
cleanup()
r=post('/dev/schema/page',{'pageNum':1,'pageSize':5,'m_LIKE_tableName':'mdev'},t)
check('Z1 自建模型清零', r['code']==0 and r['data']['recordCount']==0, str(r['data']['recordCount']))
r=post('/dev/schema/page',{'pageNum':1,'pageSize':5,'m_LIKE_tableName':'devtest_import_probe'},t)
left=r['data']['recordCount']
# importTable 历史（先删重建产生的两条：getByTableName 追加了两次 id）——remove 兜底
if left:
    for row in r['data']['rows']:
        post('/dev/schema/remove',{'ids':[int(row['id'])]},t)
    r=post('/dev/schema/page',{'pageNum':1,'pageSize':5,'m_LIKE_tableName':'devtest_import_probe'},t)
check('Z2 探针模型清零', r['data']['recordCount']==0, str(r['data']['recordCount']))
r=post('/dev/schema/page',{'pageNum':1,'pageSize':5,'m_LIKE_tableName':'sys_post'},t)
if r['data']['recordCount']:
    for row in r['data']['rows']:
        post('/dev/schema/remove',{'ids':[int(row['id'])]},t)
r=post('/dev/schema/page',{'pageNum':1,'pageSize':5,'m_LIKE_tableName':'sys_post'},t)
check('Z3 自愈 sys_post 清零', r['data']['recordCount']==0, str(r['data']['recordCount']))
r=post('/dev/schemaGroup/page',{'pageNum':1,'pageSize':5,'m_EQ_code':GC},t)
check('Z4 分组清零', r['data']['recordCount']==0, str(r['data']['recordCount']))
print('OK %d FAIL %d'%(ok,bad))
