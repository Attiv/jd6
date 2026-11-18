package.path='./lua/?.lua;'..package.path
local out={}
_G.Candidate=function(kind,a,b,text,comment) return {type=kind,text=text,comment=comment,start=a,_end=b} end
_G.yield=function(c) out[#out+1]=c end
local tools=require('xmjd6.xmjd6_tools')
local function menu(input) out={}; tools(input,{start=0,_end=#input},{}); return out end
local function contains(items,text) for _,c in ipairs(items) do if c.text==text then return true end end; return false end
local failures=0
local function test(name,fn) local ok,e=pcall(fn); print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(e))); if not ok then failures=failures+1 end end
test('exact help preserves existing command catalogue',function() assert(contains(menu('=?'),'=stats')) end)
test('stats keyword filters help',function() local m=menu('=?stats'); assert(#m==1 and m[1].text=='=stats') end)
test('date alias finds date tools',function() assert(contains(menu('=?date'),'rq')) end)
test('unknown help query returns a useful empty-state candidate',function() local m=menu('=?zzzzzzz'); assert(#m==1 and m[1].type=='tools_help_empty') end)
test('double question mark remains reserved for quick symbols',function() assert(#menu('=??')==0) end)
test('ordinary input is not intercepted',function() assert(#menu('abc')==0) end)
test('undo is discoverable',function() assert(contains(menu('=?undo'),'=undo')) end)
test('code preview help uses Tab in add without a standalone check command',function()
 local m=menu('=?preview')
 assert(#m==1 and m[1].text=='=add/编码 + Tab')
 for _,c in ipairs(menu('=?')) do assert(not c.text:find('=check',1,true)) end
end)
if failures>0 then os.exit(1) end
