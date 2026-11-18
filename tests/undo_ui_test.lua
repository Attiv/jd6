package.path='./lua/?.lua;'..package.path
local dir=os.tmpname(); os.remove(dir); assert(os.execute('mkdir -p '..dir))
_G.rime_api={get_user_data_dir=function() return dir end}
local out={}
_G.Candidate=function(kind,a,b,text,comment) return {type=kind,start=a,_end=b,text=text,comment=comment} end
_G.yield=function(c) out[#out+1]=c end
local fail=0
local function test(name,fn) local ok,e=pcall(fn); print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(e))); if not ok then fail=fail+1 end end
local function event(code) return {keycode=code,release=function() return false end,ctrl=function() return false end,alt=function() return false end,super=function() return false end} end
local selected
local ctx={input='=undo',refresh_non_confirmed_composition=function() end,get_selected_candidate=function() return selected end}
local env={engine={context=ctx}}
local function menu(input)
 ctx.input=input or '=undo'; out={}; require('xmjd6.undo').translator(ctx.input,{start=0,_end=#ctx.input},env); selected=out[1]; for _,c in ipairs(out) do if c.type=="runtime_undo" then selected=c; break end end; return out
end
local function setup()
 local f=assert(io.open(dir..'/dynamic_phrases.txt','w')); f:write('甲\tabc\n'); f:close()
 assert(require('xmjd6.dynamic_phrase_core').delete_phrase('甲','abc',dir..'/dynamic_phrases.txt',dir..'/candidate_order.txt'))
end
test('undo menu presents local history',function() setup(); assert(menu()[1].type=='runtime_undo') end)
test('one zero only previews, another key cancels',function()
 local ui=require('xmjd6.undo'); local store=require('xmjd6.runtime_store'); local count=#store.history(dir)
 menu(); assert(ui.processor(event(48),env)==1); assert(menu()[1].type=='runtime_undo_confirm'); assert(#store.history(dir)==count)
 ui.processor(event(string.byte('a')),env); assert(menu()[1].type=='runtime_undo')
end)
test('two zeros restore without committing helper text',function()
 local ui=require('xmjd6.undo'); local store=require('xmjd6.runtime_store'); local count=#store.history(dir)
 menu(); assert(ui.processor(event(48),env)==1); menu(); assert(ui.processor(event(48),env)==1)
 assert(#store.history(dir)==count-1); assert(require('xmjd6.dynamic_phrase_core').load_entries(dir..'/dynamic_phrases.txt')[1].text=='甲')
end)
test('changed input cancels pending restore and swallows stale zero',function()
 setup(); local ui=require('xmjd6.undo'); menu(); ui.processor(event(48),env)
 ctx.input='abc'; assert(ui.processor(event(48),env)==1)
 assert(#require('xmjd6.runtime_store').history(dir)>0)
end)
test('space and return do not submit helper candidates',function()
 local ui=require('xmjd6.undo'); menu(); assert(ui.processor(event(32),env)==1); assert(ui.processor(event(13),env)==1)
end)
test('normal typing outside undo passes through',function() ctx.input='abc'; assert(require('xmjd6.undo').processor(event(48),env)==2) end)
test('digit selection cannot submit management helper text',function()
 local ui=require('xmjd6.undo'); menu()
 for digit=49,57 do assert(ui.processor(event(digit),env)==1) end
end)
os.execute('rm -rf '..dir); if fail>0 then os.exit(1) end
