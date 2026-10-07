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
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # 服务与 e2e 同机：仓根下的 uploadfiles/
def upload_part_form(path,filename,content,part_number,file_info_id,token):
    """分片上传：multipart/form-data 同时带文件域与 partNumber/fileInfoId 文本域（boot2 @RequestParam 同形）"""
    b='----e2e'+uuid.uuid4().hex
    body=(('--'+b+'\r\nContent-Disposition: form-data; name="partNumber"\r\n\r\n'+str(part_number)+'\r\n'
          '--'+b+'\r\nContent-Disposition: form-data; name="fileInfoId"\r\n\r\n'+str(file_info_id)+'\r\n'
          '--'+b+'\r\nContent-Disposition: form-data; name="file"; filename="'+filename+'"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n').encode()
          +content+('\r\n--'+b+'--\r\n').encode())
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

# ── D. 分片上传四件套（UC-0604/0605；本地盘合并）──
# 雪花 id 一律按**字符串**传：MoonBit 的 Json::Number 存 Float，
# 19 位 id 走数字字面量会掉精度（全局约定 §5 本就要求字符串）
P1=b'X'*1000
P2=b'Y'*500
MFN='e2e_mp_'+uuid.uuid4().hex[:8]+'.bin'
r=post_json('/sys/fileInfo/initiateMultipartUpload',{'size':len(P1)+len(P2),'originalFilename':MFN,
                                                    'contentType':'application/octet-stream','objectType':'default'},t)
d=r.get('data') or {}
check('D1 initiate 返回 fileInfoId(str)+uploadId(str)',
      r['code']==0 and isinstance(d.get('fileInfoId'),str) and isinstance(d.get('uploadId'),str) and len(d['uploadId'])>0, str(r)[:140])
mfid=d.get('fileInfoId')
check('D1b initiate 即写 url（契约 UC-0604）',
      str((post_json('/sys/fileInfo/detail',{'id':str(mfid)},t).get('data') or {}).get('url','')).startswith('/uploadfiles/'), str(r)[:120])
# **乱序上传**：先传第 2 片再传第 1 片 —— 合并必须按 partNumber，不按到达序（契约 UC-0605）
r=upload_part_form('/sys/fileInfo/uploadPart',MFN,P2,2,mfid,t)
check('D2 uploadPart 第 2 片（先到）', r['code']==0, str(r)[:110])
r=upload_part_form('/sys/fileInfo/uploadPart',MFN,P1,1,mfid,t)
check('D3 uploadPart 第 1 片（后到）', r['code']==0, str(r)[:110])
r=post_json('/sys/fileInfo/completeMultipartUpload',{'fileInfoId':mfid},t)
d=r.get('data') or {}
check('D4 complete 返回 url+fullUrl+fileInfoId',
      r['code']==0 and str(d.get('url','')).startswith('/uploadfiles/') and d.get('fullUrl')==d.get('url') and str(d.get('fileInfoId'))==str(mfid), str(r)[:150])
murl=d.get('url') or ''
r=post_json('/sys/fileInfo/detail',{'id':str(mfid)},t)
check('D5 合并后 detail.size=真实字节数 1500（不是声明值原样）',
      r['code']==0 and str((r.get('data') or {}).get('size'))=='1500', str(r)[:140])
disk=os.path.join(ROOT,'uploadfiles',murl.split('/uploadfiles/')[-1]) if murl else ''
try:
    blob=open(disk,'rb').read()
except Exception:
    blob=b''
check('D6 落盘内容=PART1+PART2（乱序上传仍按序号拼）', blob==P1+P2, 'disk=%s len=%s'%(disk,len(blob)))
r=post_json('/sys/fileInfo/getFileInfoByIds',{'fileInfoIds':mfid},t)
got=(r.get('data') or [{}])[0]
check('D7 分片文件 getFileInfoByIds 回显 name+status=done',
      r['code']==0 and got.get('name')==MFN and got.get('status')=='done', str(r)[:140])
# 台账形状：sys_file_info 无 upload_id 列，会话号与序号清单落 attr（boot2/fastapi 同策）
r=post_json('/sys/fileInfo/detail',{'id':str(mfid)},t)
attr=str((r.get('data') or {}).get('attr') or '')
# 清单按**到达序**记（先 2 后 1），排序发生在合并那一步——由 D6 的落盘内容证明
# 清单按**到达序**记（先 2 后 1），排序发生在合并那一步——由 D6 的落盘内容证明
import re as _re
m_parts=_re.search(r'"parts":"([0-9,]*)"', attr)
plist=sorted((m_parts.group(1).split(',') if m_parts else []))
check('D8 attr 带 uploadId 且序号清单不重复（到达序）',
      '"uploadId"' in attr and plist==['1','2'], attr[:120])
r=post_json('/sys/fileInfo/remove',{'ids':[str(mfid)]},t)
check('D9 合并结果可 remove', r['code']==0, str(r)[:80])

# abort 对照：initiate → 传 1 片 → abort → 台账与暂存都不留
ABN='e2e_abort_'+uuid.uuid4().hex[:8]+'.bin'
r=post_json('/sys/fileInfo/initiateMultipartUpload',{'size':10,'originalFilename':ABN,
                                                    'contentType':'application/octet-stream','objectType':'default'},t)
abid=(r.get('data') or {}).get('fileInfoId')
abup=(r.get('data') or {}).get('uploadId')
check('D10 abort 前置 initiate', r['code']==0 and abid and abup, str(r)[:90])
r=upload_part_form('/sys/fileInfo/uploadPart',ABN,b'Z'*10,1,abid,t)
check('D11 abort 前置 uploadPart', r['code']==0, str(r)[:90])
staged=os.path.join(ROOT,'uploadfiles','.multipart')
r=post_json('/sys/fileInfo/abortMultipartUpload',{'fileInfoId':abid},t)
check('D12 abort code=0', r['code']==0, str(r)[:90])
r=post_json('/sys/fileInfo/page',{'pageNum':1,'pageSize':500,'m_LIKE_originalFilename':ABN},t)
check('D13 abort 后台账行消失（契约"删除记录"）', r['code']==0 and (r.get('data') or {}).get('rows')==[], str(r)[:110])
r=post_json('/sys/fileInfo/abortMultipartUpload',{'fileInfoId':abid},t)
check('D14 abort 对已删行再取消＝业务失败非 0', r['code']!=0, str(r)[:90])
check('D15 取消后暂存目录已清（不留平台侧残留）',
      not os.path.isdir(os.path.join(staged,str(abup))),
      'staged=%s/%s 应已不存在'%(staged,abup))

# 负向：会话不存在 / 无分片就 complete
r=upload_part_form('/sys/fileInfo/uploadPart',MFN,b'x',1,'999999999999',t)
check('D16 uploadPart 打到不存在 fileInfoId → 非 0', r['code']!=0, str(r)[:90])
r=post_json('/sys/fileInfo/completeMultipartUpload',{'fileInfoId':999999999999},t)
check('D17 complete 打到不存在 fileInfoId → 非 0', r['code']!=0, str(r)[:90])
r3=post_json('/sys/fileInfo/initiateMultipartUpload',{'size':10,'originalFilename':'e2e_empty.bin','contentType':'application/octet-stream'},t)
e3=(r3.get('data') or {}).get('fileInfoId')
r=post_json('/sys/fileInfo/completeMultipartUpload',{'fileInfoId':e3},t)
check('D18 一片未传就 complete → 业务失败（"没有可合并的分片"）', r['code']!=0, str(r)[:110])
r=post_json('/sys/fileInfo/remove',{'ids':[str(e3)]},t)
check('D19 清理空会话台账行', r['code']==0, str(r)[:80])
# 未登录：四件套都要登录
r=post_json('/sys/fileInfo/initiateMultipartUpload',{'size':1,'originalFilename':'x.bin'},'garbage')
check('D20 未登录 initiate 99990403', r['code']==99990403, str(r)[:90])

print('OK %d FAIL %d'%(ok,bad))
