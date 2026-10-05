# -*- coding: utf-8 -*-
# RBAC 授权面矩阵：saveRoleMenu/roleMenuIds/saveUserRole/removeUserRole/userListByRoleId/
# userListExcludeRoleId/grantDataScope（boot2 RbacController + RoleController#grantDataScope 同位）
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
RN='mrrole'+str(int(time.time())%100000)
UN='mruser'+str(int(time.time())%100000)

# ---- 角色 + 菜单授权往返 ----
rid=post('/sys/role/save',{'name':RN,'code':RN,'enabled':1},t)['data']
check('R1 role save', rid is not None and str(rid).isdigit(), str(rid))
# 借管理员角色的 roleMenuIds 拿真实菜单 id 当授权料
admin_menus=post('/sys/rbac/roleMenuIds',{'roleId':'1705019929250172930'},t)['data']
menu_id=admin_menus[0]
r=post('/sys/rbac/saveRoleMenu',[{'roleId':rid,'menuId':menu_id}],t)
check('R2 saveRoleMenu 顶层数组', r['code']==0, str(r))
r=post('/sys/rbac/roleMenuIds',{'roleId':rid},t)
check('R3 roleMenuIds 回读', r['code']==0 and menu_id in r['data'], str(r)[:120])
r=post('/sys/rbac/saveRoleMenu',[{'roleId':rid}],t)
check('R4 saveRoleMenu 空补清空', r['code']==0, str(r))
r=post('/sys/rbac/roleMenuIds',{'roleId':rid},t)
check('R5 清空后空数组', r['code']==0 and r['data']==[], str(r))
# {list:[...]} 形状兼容（vben5 双形态）
r=post('/sys/rbac/saveRoleMenu',{'list':[{'roleId':rid,'menuId':menu_id}]},t)
r2=post('/sys/rbac/roleMenuIds',{'roleId':rid},t)
check('R6 saveRoleMenu list 形状', r['code']==0 and menu_id in r2['data'], str(r2)[:120])

# ---- 用户-角色授权往返 ----
uid=post('/sys/user/save',{'userName':UN,'realName':'rbac矩阵','mobilePhone':'13900001111'},t)['data']
check('R7 user save', uid is not None)
r=post('/sys/rbac/saveUserRole',[{'userId':uid,'roleId':rid}],t)
check('R8 saveUserRole', r['code']==0, str(r))
r=post('/sys/rbac/userListByRoleId',{'roleId':rid},t)
check('R9 userListByRoleId 含新用户', r['code']==0 and any(str(x['id'])==uid for x in r['data']['rows']), str(r)[:120])
r=post('/sys/rbac/userListByRoleId',{'roleId':rid,'keywords':'rbac'},t)
check('R10 userListByRoleId keywords', r['code']==0 and len(r['data']['rows'])==1, str(r)[:120])
r=post('/sys/rbac/userListExcludeRoleId',{'roleId':rid},t)
check('R11 userListExcludeRoleId 不含', r['code']==0 and not any(str(x['id'])==uid for x in r['data']['rows']), str(r)[:80])
r=post('/sys/rbac/removeUserRole',[{'userId':uid,'roleId':rid}],t)
r2=post('/sys/rbac/userListByRoleId',{'roleId':rid},t)
check('R12 removeUserRole 生效', r['code']==0 and r2['data']['rows']==[], str(r2))

# ---- grantDataScope（sys_role.data_scope 直更 + sys_role_dept 全量替换）----
dept_id=post('/sys/dept/select',{'pageSize':1},t)['data'][0]['value']
r=post('/sys/role/grantDataScope',{'id':rid,'dataScope':5,'deptIdList':[dept_id]},t)
check('R13 grantDataScope 0', r['code']==0, str(r))
r=post('/sys/role/detail',{'id':rid},t)
check('R14 dataScope 持久化', r['code']==0 and r['data']['dataScope']==5, str(r['data'])[:120])
r=post('/sys/role/grantDataScope',{'id':rid,'dataScope':None,'deptIdList':[]},t)
r2=post('/sys/role/detail',{'id':rid},t)
check('R15 dataScope 缺省不覆盖', r['code']==0 and r2['data']['dataScope']==5, str(r2['data'])[:80])
r=post('/sys/role/grantDataScope',{'id':'999','dataScope':1},t)
check('R16 grantDataScope 未知角色 0（幂等）', r['code']==0, str(r))

# ---- dept/tree 双码 OR（sys:dept:tree OR sys:role:grantDataScope）----
r=post('/sys/dept/tree',{},t)
check('R17 dept/tree 形状', r['code']==0 and isinstance(r['data'],list) and len(r['data'])>=1, str(r)[:80])
check('R18 tree 节点含 children', 'children' in r['data'][0] and r['data'][0].get('id') is not None, str(r['data'][0])[:100])

# ---- 部门排序（autoSort/updateSort）----
r=post('/sys/dept/autoSort',{},t)
check('R19 autoSort 0', r['code']==0, str(r))
r=post('/sys/dept/tree',{},t)
check('R20 autoSort 后 sort=层级*10000+层内*1000', r['data'][0]['sort']=='10000', str(r['data'][0]['sort']))
r=post('/sys/dept/updateSort',[{'id':r['data'][0]['id'],'sort':77700}],t)
r2=post('/sys/dept/tree',{},t)
check('R21 updateSort 直更', r['code']==0 and r2['data'][0]['sort']=='77700', str(r2['data'][0]['sort']))
r=post('/sys/dept/autoSort',{},t)
check('R22 复位 autoSort', r['code']==0)

# ---- 清理 ----
post('/sys/role/remove',{'ids':[rid]},t)
post('/sys/user/remove',{'ids':[uid]},t)
r=post('/sys/role/detail',{'id':rid},t)
check('R23 清理后查不到（逻辑删）', r['code']!=0 or r['data'] in (None,{}), str(r)[:80])

print('OK %d FAIL %d'%(ok,bad))
