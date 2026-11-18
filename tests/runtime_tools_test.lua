package.path = './lua/?.lua;' .. package.path
local dir = os.tmpname(); os.remove(dir); assert(os.execute('mkdir -p ' .. dir))
_G.rime_api = {get_user_data_dir=function() return dir end}
package.preload.lfs = function() error('lfs intentionally unavailable') end
local function read(p) local f=io.open(p,'rb'); if not f then return nil end; local s=f:read('*a'); f:close(); return s end
local function write(p,s) local f=assert(io.open(p,'wb')); assert(f:write(s)); assert(f:close()) end
local function eq(a,b) assert(a==b, tostring(a)..' ~= '..tostring(b)) end
local passed,failed=0,0
local raw_open,raw_rename,raw_config=io.open,os.rename,package.config
local function test(name,fn)
 local ok,e=pcall(fn); io.open,os.rename,package.config=raw_open,raw_rename,raw_config; if ok then passed=passed+1; print('PASS '..name) else failed=failed+1; print('FAIL '..name..': '..tostring(e)) end
end
local function store() return require('xmjd6.runtime_store') end
local dp=dir..'/dynamic_phrases.txt'; local cp=dir..'/candidate_order.txt'
local dynamic=require('xmjd6.dynamic_phrase_core')
test('same-size external phrase edits refresh without lfs',function()
 write(dp,'甲\tabc\n'); eq(dynamic.load_entries(dp)[1].text,'甲')
 write(dp,'乙\tabc\n'); eq(dynamic.load_entries(dp)[1].text,'乙')
end)
local co=require('xmjd6.candidate_order_core')
test('same-size external tuning edits refresh without lfs',function()
 write(cp,'甲\tabcd\t乙\tabc\tabcdi\n'); eq(co.load().records[1].promoted,'甲')
 write(cp,'丙\tabcd\t乙\tabc\tabcdi\n'); eq(co.load().records[1].promoted,'丙')
end)
test('checked replacement keeps last good backup',function()
 local p=dir..'/safe'; write(p,'old'); assert(store().write(p,'new')); eq(read(p),'new'); eq(read(p..'.bak'),'old')
end)
test('failed rename leaves original intact',function()
 local p=dir..'/safe'; local rename=os.rename
 os.rename=function() return nil,'injected rename failure' end
 local ok=store().write(p,'lost'); os.rename=rename
 eq(ok,false); eq(read(p),'new')
end)
test('failed temporary write leaves original intact',function()
 local p=dir..'/safe'; local open=io.open
 io.open=function(path,mode)
  if mode=='wb' then return {write=function() return nil,'disk full' end,close=function() return true end} end
  return open(path,mode)
 end
 local ok=store().write(p,'lost'); io.open=open
 eq(ok,false); eq(read(p),'new')
end)
test('deletion and dependent tuning form one recoverable operation',function()
 write(dp,'甲\tabc\n乙\tdef\n'); write(cp,'甲\tabci\t丙\tabc\tabcu\n')
 dynamic.clear_cache(); co.clear_cache()
 assert(dynamic.delete_phrase('甲','abc',dp,cp)); eq(#dynamic.load_entries(dp),1); eq(#co.load().records,0)
 local h=store().history(dir); eq(#h,1)
 assert(store().undo(h[1].id,dir)); eq(#dynamic.load_entries(dp),2); eq(#co.load().records,1)
end)
test('undo preserves unrelated external edits and comments',function()
 write(dp,'甲\tabc\n乙\tdef\n'); write(cp,''); dynamic.clear_cache()
 assert(dynamic.delete_phrase('甲','abc',dp,cp))
 write(dp,assert(read(dp))..'# external comment\n丙\tghi\n')
 assert(store().undo(store().history(dir)[1].id,dir))
 local s=assert(read(dp)); assert(s:find('甲\tabc',1,true)); assert(s:find('丙\tghi',1,true)); assert(s:find('# external comment',1,true))
end)
test('undo tuning rejects divergent same-target external edit',function()
 write(cp,'乙\tabci\t甲\tabc\tabcu\n'); co.clear_cache()
 assert(co.remove_record_and_dependents(co.load().records[1],cp))
 local h=store().history(dir); local id=h[1].id
 write(cp,'丙\tabci\t甲\tabc\tabcu\n')
 local ok=store().undo(id,dir); eq(ok,false); eq(read(cp),'丙\tabci\t甲\tabc\tabcu\n')
 eq(store().history(dir)[1].id,id)
end)
test('read errors cannot turn a runtime file into an empty overwrite',function()
 local original=assert(read(dp)); local open=io.open
 io.open=function(path,mode) if path==dp and (mode=='r' or mode=='rb') then return nil,'denied',13 end; return open(path,mode) end
 local ok=dynamic.add_phrase('丁','jkl',dp); io.open=open
 eq(ok,false); eq(read(dp),original)
end)
test('history retains only the latest 20 local operations',function()
 write(cp,''); write(dp,''); dynamic.clear_cache(); co.clear_cache()
 for i=1,25 do assert(dynamic.add_phrase('词'..i,'abc'..i,dp)); assert(dynamic.delete_phrase('词'..i,'abc'..i,dp,cp)) end
 eq(#store().history(dir),20)
end)
test('multi-file failure rolls back the first file and records no undo',function()
 local a,b=dir..'/a',dir..'/b'; write(a,'甲\tabc\n'); write(b,'乙\tdef\n')
 local count=#store().history(dir); local rename=os.rename
 os.rename=function(src,dst) if dst==b and src:find('.tmp',1,true) then return nil,'injected' end; return rename(src,dst) end
 local ok=store().perform('fault',{{path=a,kind='phrases'},{path=b,kind='phrases'}},function()
  assert(store().write(a,'丙\tabc\n')); assert(store().write(b,'丁\tdef\n')); return true
 end,true)
 os.rename=rename; eq(ok,false); eq(read(a),'甲\tabc\n'); eq(read(b),'乙\tdef\n'); eq(#store().history(dir),count)
end)
test('failed close leaves the original intact',function()
 local p=dir..'/safe'; local open=io.open
 io.open=function(path,mode)
  if mode=='wb' then local f=assert(open(path,mode)); return {write=function(_,s) return f:write(s) end,close=function() f:close(); return nil,'close failed' end} end
  return open(path,mode)
 end
 local ok=store().write(p,'lost'); io.open=open; eq(ok,false); eq(read(p),'new')
end)
test('interrupted transaction recovers all files and its undo entry',function()
 local a,b=dir..'/recover-a',dir..'/recover-b'; write(a,'甲\tabc\n'); write(b,'乙\tdef\n')
 local rename=os.rename
 os.rename=function(src,dst)
  if dst==b or (dst==a and read(src)=='甲\tabc\n') then return nil,'injected interruption' end
  return rename(src,dst)
 end
 local ok=store().perform('recovery fixture',{{path=a,kind='phrases'},{path=b,kind='phrases'}},function()
  assert(store().write(a,'丙\tabc\n')); assert(store().write(b,'丁\tdef\n')); return true
 end,true)
 os.rename=rename; eq(ok,false); assert(read(dir..'/runtime_tools.transaction'))
 assert(store().recover(dir)); eq(read(a),'丙\tabc\n'); eq(read(b),'丁\tdef\n')
 eq(store().history(dir)[1].label,'recovery fixture')
end)
test('undoing a newly added rule rejects a concurrent same-target rule',function()
 write(cp,''); co.clear_cache()
 assert(co.append_order({promoted='甲',old_code='abci',displaced='乙',target_code='abc',new_code='abcu'},cp))
 local h=store().history(dir); local id=h[1].id
 write(cp,read(cp)..'丙\tabci\t乙\tabc\tabcu\n')
 local ok=store().undo(id,dir); eq(ok,false); assert(read(cp):find('甲',1,true))
end)
test('undo journal survives module reload without executable data',function()
 local before=store().history(dir); package.loaded['xmjd6.runtime_store']=nil
 local after=store().history(dir); eq(after[1].id,before[1].id)
 local raw=read(dir..'/runtime_undo.tsv'); assert(raw:find('XMJD6_UNDO_1',1,true))
end)
test('undo restores legacy space-separated tuning records',function()
 write(cp,'甲 abci 乙 abc abcu\n'); co.clear_cache()
 assert(co.append_order({promoted='丙',old_code='abci',displaced='乙',target_code='abc',new_code='abcu'},cp))
 assert(store().undo(store().history(dir)[1].id,dir))
 eq(co.load().records[1].promoted,'甲')
end)
test('space-separated external tuning rules cannot bypass conflict checking',function()
 write(cp,'甲\tabci\t乙\tabc\tabcu\n'); co.clear_cache()
 assert(co.remove_record_and_dependents(co.load().records[1],cp))
 local id=store().history(dir)[1].id
 write(cp,'丙 abci 乙 abc abcu\n')
 local ok=store().undo(id,dir); eq(ok,false); eq(read(cp),'丙 abci 乙 abc abcu\n')
end)
test('recovery history is searchable by affected code',function()
 write(dp,'甲\tsearchcode\n'); write(cp,''); dynamic.clear_cache(); co.clear_cache()
 assert(dynamic.delete_phrase('甲','searchcode',dp,cp))
 eq(#store().history(dir,'searchcode'),1)
end)
test('Windows replacement survives an interruption after parking the original',function()
 local p=dir..'/windows-safe'; write(p,'last good'); local rename=os.rename
 package.config='\\'..raw_config:sub(2)
 os.rename=function(src,dst)
  if read(dst)~=nil then return nil,'destination exists' end
  local ok,err=rename(src,dst)
  if src==p and dst==p..'.replace-old' then error('simulated process interruption') end
  return ok,err
 end
 local ok=pcall(store().write,p,'pending'); os.rename=rename
 eq(ok,false); eq(store().read(p),'last good')
 assert(store().write(p,'next good')); eq(read(p),'next good')
end)
test('a copied foreign undo journal does not block new local operations',function()
 local foreign=dir..'/foreign'; assert(os.execute('mkdir -p '..foreign))
 write(foreign..'/runtime_undo.tsv',assert(read(dir..'/runtime_undo.tsv')))
 local p,c=foreign..'/dynamic_phrases.txt',foreign..'/candidate_order.txt'
 write(p,'甲\tabc\n'); write(c,''); dynamic.clear_cache()
 assert(dynamic.delete_phrase('甲','abc',p,c))
 eq(#store().history(foreign),1)
 assert(read(foreign..'/runtime_undo.tsv.foreign.bak'))
end)
os.execute('rm -rf '..dir)
print(string.format('%d passed, %d failed',passed,failed)); if failed>0 then os.exit(1) end
