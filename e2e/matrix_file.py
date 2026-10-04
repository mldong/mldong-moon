# -*- coding: utf-8 -*-
# 文件矩阵（~9 例）——upload multipart / getFileInfoByIds / remove / 负向；boot2 FileInfo 对齐
import json,urllib.request,os,uuid
B=os.environ.get('BASE','http://127.0.0.1:18680')
def post_json(path,body,token=None):
    r=urllib.request.Request(B+path,data=json.dumps(body).encode(),method='POST')
    r.add_header('Content-Type','application/json')
    if token: r.add_header('Authorization','Bearer '+token)
    try:
        with urllib.request.urlopen(r) as resp: return json.load(resp)
    except urllib.error.HTTPError as e:
        try: return json.load(e)
        except: return {'code':e.code}
def upload(path,filename,content,token):
    b='----e2e'+uuid.uuid4().hex
    body=('--'+b+'\r\nContent-Disposition: form-data; name="file"; filename="'+filename+'"\r\n'
          'Content-Type: text/plain\r\n\r\n'+content+'\r\n'
          '--'+b+'\r\nContent-Disposition: form-data; name="objectType"\r\n\r\ndefault\r\n'
          '--'+b+'--\r\n').encode()
    r=urllib.request.Request(B+path,data=body,method='POST')
    r.add_header('Content-Type','multipart/form-data; boundary='+b)
    r.add_header('Authorization','Bearer '+token)
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

t=post_json('/sys/login',{'userName':'superAdmin','password':'123456'})['data']['token']
FN='e2e_'+uuid.uuid4().hex[:8]+'.txt'
CONTENT='contract file content 测试内容'

# ── A. upload 契约（UC-0601）──
r=upload('/sys/fileInfo/upload',FN,CONTENT,t)
check('A1 upload code=0 + url/fileInfoId', r['code']==0 and isinstance(r['data'],dict) and 'url' in r['data'] and isinstance(r['data']['fileInfoId'],str), str(r)[:110])
fid=r['data']['fileInfoId'] if r['code']==0 else None
check('A2 url 形状 /uploadfiles/yyyyMM/', r['code']==0 and r['data']['url'].startswith('/uploadfiles/') and r['data']['url'].endswith('.txt'), str(r.get('data',{}).get('url')))

# ── B. getFileInfoByIds 契约（UC-0602/0606）──
r=post_json('/sys/fileInfo/getFileInfoByIds',{'fileInfoIds':fid},t)
check('B1 回查单行 Ant 形状', r['code']==0 and isinstance(r['data'],list) and len(r['data'])==1 and all(k in r['data'][0] for k in ('id','uid','name','url','status')), str(r)[:140])
if r['code']==0 and r['data']:
    check('B2 原文件名保留 + status done', r['data'][0]['name']==FN and r['data'][0]['status']=='done', str(r['data'][0])[:110])
# 逗号多 id 批量
r2=upload('/sys/fileInfo/upload','e2e_b.txt','second',t)
fid2=r2['data']['fileInfoId'] if r2['code']==0 else None
r=post_json('/sys/fileInfo/getFileInfoByIds',{'fileInfoIds':fid+','+fid2},t)
check('B3 逗号串批量回查', r['code']==0 and len(r['data'])==2, str(r)[:110])
# 未知 id → 空表
r=post_json('/sys/fileInfo/getFileInfoByIds',{'fileInfoIds':'12345'},t)
check('B4 未知 id 空表', r['code']==0 and r['data']==[], str(r)[:80])

# ── C. remove（runner finally 同款）──
r=post_json('/sys/fileInfo/remove',{'ids':[int(fid),int(fid2)]},t)
check('C1 remove code=0', r['code']==0, str(r)[:80])
r=post_json('/sys/fileInfo/getFileInfoByIds',{'fileInfoIds':fid+','+fid2},t)
check('C2 删除后回查空', r['code']==0 and r['data']==[], str(r)[:80])
# 未登录 upload 99990403
r=upload('/sys/fileInfo/upload','x.txt','x','garbage')
check('C3 未登录 99990403', r['code']==99990403, str(r)[:80])
print('OK %d FAIL %d'%(ok,bad))
