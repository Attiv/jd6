package.path='./lua/?.lua;'..package.path
local dir=os.tmpname(); os.remove(dir); assert(os.execute('mkdir -p '..dir))
_G.rime_api={get_user_data_dir=function() return dir end}
local co=require('xmjd6.candidate_order_core')
local function write(name,text) local f=assert(io.open(dir..'/'..name,'w')); f:write(text); f:close() end
for _,name in ipairs(co.occupied_dict_files) do write(name,'') end
write('xmjd6.cx.dict.yaml','甲\tjavi\n乙\tyiua\n')
write('xmjd6.danzi.dict.yaml','甲\tjavi\n乙\tyiua\n')
write('xmjd6.cizu.dict.yaml','旧词\tjayi\n占用\tjayiv\n')
write('xmjd6.extended.dict.yaml','---\nimport_tables:\n  - xmjd6.cizu\n')
write('dynamic_phrases.txt','自造词\tjayi\n')
write('candidate_order.txt','')
local failures=0
local function test(name,fn) local ok,e=pcall(fn); print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(e))); if not ok then failures=failures+1 end end
local function preview() return require('xmjd6.code_preview') end
test('preview combines static and dynamic occupants and derives only a free valid suffix',function()
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir}))
 assert(result.occupants.jayi['旧词'] and result.occupants.jayi['自造词'])
 assert(#result.available==1 and result.available[1]=='jayivu')
end)
test('preview applies tuning overlay without changing files',function()
 write('candidate_order.txt','调上\tjayiua\t旧词\tjayi\tjayiv\n'); co.clear_cache()
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir}))
 assert(result.occupants.jayi['调上'] and not result.occupants.jayi['旧词'])
 local f=assert(io.open(dir..'/candidate_order.txt')); assert(f:read('*a')=='调上\tjayiua\t旧词\tjayi\tjayiv\n'); f:close()
end)
test('incomplete source inspection never guarantees an available code',function()
 os.remove(dir..'/xkjd6.lanlao.dict.yaml')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir})); assert(not result.complete and #result.available==0)
 write('xkjd6.lanlao.dict.yaml','')
end)
test('topup preview uses the same decision as the actual processor',function()
 local point=preview().topup_point('bcae',{protected_codes={},topup_set={a=true,i=true,u=true,o=true,v=true},topup_min=4,topup_min_danzi=2,topup_max=10,alphabet={b=true,c=true,a=true,e=true}})
 assert(point==4)
end)
test('ordinary command letters do not trigger a dictionary scan',function()
 local ui=preview(); local original=ui.inspect; local count=0
 ui.inspect=function(...) count=count+1; return original(...) end
 local ctx={input='=add/jayi'}; local env={engine={context=ctx}}
 local key={keycode=97,release=function() return false end,ctrl=function() return false end,alt=function() return false end,super=function() return false end}
 assert(ui.processor(key,env)==2); assert(count==0); ui.inspect=original
end)
test('unknown imported dictionaries prevent a false free-code guarantee',function()
 write('xmjd6.extended.dict.yaml','---\nimport_tables:\n  - another.custom\n')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir})); assert(not result.complete and #result.available==0)
 write('xmjd6.extended.dict.yaml','---\nimport_tables:\n  - xmjd6.cizu\n')
end)
test('only Tab during add explicitly refreshes the preview',function()
 local ui=preview(); local original=ui.inspect; local count=0
 ui.inspect=function(...) count=count+1; return original(...) end
 _G.__dynamic_phrase_state={commit_history={'甲乙'}}
 local ctx={input='=add/jayi',refresh_non_confirmed_composition=function() end}; local env={engine={context=ctx}}
 local function key(code) return {keycode=code,release=function() return false end,ctrl=function() return false end,alt=function() return false end,super=function() return false end} end
 assert(ui.processor(key(0xff09),env)==1 and count==1)
 assert(ui.processor(key(0xff09),env)==1 and count==2)
 assert(ui.processor(key(59),env)==2 and count==2)
 assert(ctx.input=='=add/jayi')
 ui.inspect=original
end)
test('removed standalone check command passes through without scan or preview',function()
 local ui=preview(); local original=ui.inspect; local scans,emitted=0,0
 ui.inspect=function() scans=scans+1; return {} end
 local old_candidate,old_yield=_G.Candidate,_G.yield
 _G.Candidate=function() return {} end; _G.yield=function() emitted=emitted+1 end
 local ctx={input='=check/jayi'}; local env={engine={context=ctx}}
 local ok,err=pcall(function()
  for _,code in ipairs({0xff09,59,32,13,49}) do
   local key={keycode=code,release=function() return false end,ctrl=function() return false end,alt=function() return false end,super=function() return false end}
   assert(ui.processor(key,env)==2,'removed command must not intercept keys')
  end
  ui.translator(ctx.input,{start=0,_end=#ctx.input},env)
  assert(scans==0 and emitted==0)
 end)
 ui.inspect=original; _G.Candidate=old_candidate; _G.yield=old_yield
 assert(ok,err)
end)
test('disabled tuning does not hide source occupants',function()
 write('xmjd6.cizu.dict.yaml','占用\tjayiv\n'); write('candidate_order.txt','占用\tjayiv\t别词\tother\tothera\n')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir,order_enabled=false}))
 assert(result.occupants.jayiv['占用'] and #result.available==1 and result.available[1]=='jayivu')
end)
test('custom dynamic store is used rather than the default file',function()
 write('candidate_order.txt',''); write('xmjd6.cizu.dict.yaml',''); write('mine.txt','自定义\tjayiv\n')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir,dynamic_file='mine.txt'}))
 assert(result.occupants.jayiv['自定义'] and #result.available==1 and result.available[1]=='jayivu')
end)
test('inline YAML imports cannot bypass incomplete-inspection warnings',function()
 write('xmjd6.extended.dict.yaml','import_tables: [xmjd6.cizu, another.custom]\n')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir})); assert(not result.complete and #result.available==0)
 write('xmjd6.extended.dict.yaml','import_tables:\n  - xmjd6.cizu\n')
end)
test('unresolved legacy tuning fallback cannot be called a guaranteed free code',function()
 write('candidate_order.txt','调上\tjayiua\t旧词\tjayi\n')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir})); assert(not result.complete and #result.available==0)
end)
test('nested dictionary imports cannot hide unscanned occupants',function()
 write('candidate_order.txt',''); write('xmjd6.cizu.dict.yaml','---\nimport_tables:\n  - another.custom\n...\n')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir})); assert(not result.complete and #result.available==0)
end)
test('tabs in header comments cannot hide nested imports',function()
 write('xmjd6.cizu.dict.yaml','# dictionary header\tcomment\nname:\tfixture\nimport_tables:\n  - another.custom\n...\n')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir})); assert(not result.complete and #result.available==0)
end)
test('quoted or unsupported YAML header keys fail closed',function()
 for _,header in ipairs({'"import_tables":\n  - another.custom\n','<<: *imports\n','!!map {import_tables: [another.custom]}\n'}) do
  write('xmjd6.cizu.dict.yaml','---\n'..header..'...\n')
  local result=assert(preview().inspect('甲乙','jayi',{dir=dir})); assert(not result.complete and #result.available==0)
 end
end)
test('shipped encoder metadata is supported with explicit source codes',function()
 write('xmjd6.cizu.dict.yaml','甲乙\tjayi\n')
 write('candidate_order.txt','')
 local f=assert(io.open('xmjd6.extended.dict.yaml')); local header=f:read('*a'); f:close()
 write('xmjd6.extended.dict.yaml',header)
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir}))
 assert(result.complete and #result.available>0,'default encoder must not disable explicit-source preview')
end)
test('unknown encoder structures still fail closed',function()
 local headers={
  'encoder:\n  rules:\n    - length_equal: 2\n      formula: "Unknown"\n',
  'encoder:\n  import_tables:\n    - another.custom\n',
 }
 for _,header in ipairs(headers) do
  write('xmjd6.extended.dict.yaml',header..'import_tables:\n  - xmjd6.cizu\n')
  local result=assert(preview().inspect('甲乙','jayi',{dir=dir}))
  assert(not result.complete and #result.available==0)
 end
end)
test('explicit nonalphabet symbol codes do not imply automatic encoding',function()
 write('xmjd6.extended.dict.yaml','import_tables:\n  - xmjd6.cizu\n')
 write('xmjd6.cizu.dict.yaml','---\nname: fixture\n...\n符号\t/fh\n')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir}))
 assert(result.complete and #result.available>0)
end)
test('digit codes that may derive lowercase spellings fail closed',function()
 write('xmjd6.extended.dict.yaml','import_tables:\n  - xmjd6.cizu\n')
 write('xmjd6.cizu.dict.yaml','---\nname: fixture\n...\n隐藏占用\tjayiv1\n')
 local result=assert(preview().inspect('甲乙','jayi',{dir=dir}))
 assert(not result.complete and #result.available==0,'derive/[0-9]$// can occupy the lowercase code')
end)
test('implicit or malformed source codes cannot be called free',function()
 write('xmjd6.extended.dict.yaml','import_tables:\n  - xmjd6.cizu\n')
 for _,rows in ipairs({'睚眦\n','狴犴\t\n','实线\t\tekxmoa\n'}) do
  write('xmjd6.cizu.dict.yaml','---\nname: fixture\n...\n'..rows)
  local result=assert(preview().inspect('甲乙','jayi',{dir=dir}))
  assert(not result.complete and #result.available==0,'unscanned automatic encodings need a warning')
 end
end)
os.execute('rm -rf '..dir); if failures>0 then os.exit(1) end
