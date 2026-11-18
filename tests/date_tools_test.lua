package.path='./lua/?.lua;'..package.path
local failures=0
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function test(name,fn) local ok,e=pcall(fn); print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(e))); if not ok then failures=failures+1 end end
local function m() return require('xmjd6.date_tools') end
test('date addition crosses leap day and year boundaries',function() eq(m().add('20240228',1),'2024-02-29'); eq(m().add('20241231',1),'2025-01-01'); eq(m().add('20240101',-1),'2023-12-31') end)
test('Gregorian century leap rule and bad date rejection',function() eq(m().add('19000228',1),'1900-03-01'); eq(m().add('20000228',1),'2000-02-29'); assert(m().parse('20260229')==nil); assert(m().parse('20261301')==nil) end)
test('signed difference counts calendar dates',function() eq(m().difference('20261022','20261101'),10); eq(m().difference('20261101','20261022'),-10) end)
test('week starts Monday and ends Sunday',function() local a,b=m().week('20261022'); eq(a,'2026-10-19'); eq(b,'2026-10-25') end)
test('out of range addition is rejected',function() assert(m().add('00010101',-1)==nil); assert(m().add('99991231',1)==nil) end)
test('translator handles day week and difference syntax',function()
 local out={}; _G.Candidate=function(kind,a,b,text,comment) return {type=kind,text=text,comment=comment} end; _G.yield=function(c) out[#out+1]=c end
 local function menu(s) out={}; m().translator(s,{start=0,_end=#s},{}); return out end
 eq(menu('=20261022+7d')[1].text,'2026-10-29'); eq(menu('=20261022-2w')[1].text,'2026-10-08')
 eq(menu('=diff/20261022/20261101')[1].text,'10天')
 assert(#menu('=20261022')==0); assert(#menu('=1+1')==0); assert(#menu('=5~3')==0)
 assert(menu('=20260229+1d')[1].type=='date_tools_error')
end)
if failures>0 then os.exit(1) end
