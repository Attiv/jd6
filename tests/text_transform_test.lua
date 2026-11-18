package.path='./lua/?.lua;'..package.path
local m=require('xmjd6.text_transform')
local failures=0
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function test(name,fn) local ok,e=pcall(fn); print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(e))); if not ok then failures=failures+1 end end
test('trim Unicode edge whitespace without touching internal spaces',function() eq(m.trim('　\t甲 乙\194\160'),'甲 乙') end)
test('merge CRLF CR and LF into one line',function() eq(m.single_line(' 甲\r\n 乙\r丙\n丁 '),'甲 乙 丙 丁') end)
test('ASCII width conversion preserves Chinese and emoji',function() eq(m.to_fullwidth('A 1!中🙂'),'Ａ　１！中🙂'); eq(m.to_halfwidth('Ａ　１！中🙂'),'A 1!中🙂') end)
test('JSON escapes controls and quotes without outer quotes',function() eq(m.json_escape('a"\\\n\t\0中'),'a\\"\\\\\\n\\t\\u0000中') end)
test('URL component encoding uses UTF8 bytes and preserves unreserved ASCII',function() eq(m.url_encode('中文 /?a=1+2~'),'%E4%B8%AD%E6%96%87%20%2F%3Fa%3D1%2B2~') end)
test('invalid UTF8 fails safely for Unicode transformations',function() local value,err=m.to_fullwidth('\255'); assert(value==nil and err) end)
test('palette preserves original first wrapper and labels new operations',function()
 local out={}; _G.Candidate=function(kind,a,b,text,comment) return {type=kind,text=text,comment=comment} end; _G.yield=function(c) out[#out+1]=c end
 _G.__dynamic_phrase_state={commit_history={' 甲\n乙 '}}
 m.translator('=wrap',{start=0,_end=5},{})
 eq(out[1].text,'“ 甲\n乙 ”'); local found=false
 for _,c in ipairs(out) do if c.text=='甲 乙' and c.comment:find('单行',1,true) then found=true end end
 assert(found)
end)
if failures>0 then os.exit(1) end
