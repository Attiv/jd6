-- Test runner supplies TZ=America/New_York for the DST boundary regression.
package.path='./lua/?.lua;'..package.path
local dir=os.tmpname(); os.remove(dir); assert(os.execute('mkdir -p '..dir))
local raw_time,raw_date=os.time,os.date
local fixed=raw_time({year=2026,month=3,day=9,hour=0,min=30,sec=0,isdst=true})
os.time=function(value) return value and raw_time(value) or fixed end
os.date=function(format,timestamp) return raw_date(format,timestamp or fixed) end
_G.rime_api={get_user_data_dir=function() return dir end}
_G.Candidate=function(kind,a,b,text,comment) return {type=kind,text=text,comment=comment} end
local out={}; _G.yield=function(c) out[#out+1]=c end
local f=assert(io.open(dir..'/typing_stats.txt','w'))
f:write('2026-03-02\t100\t100\t1\t0\t0\n2026-03-03\t1\t1\t1\t0\t0\n2026-03-09\t1\t1\t1\t0\t0\n'); f:close()
local ok,err=pcall(function()
 require('xmjd6.typing_stats').translator('=stats',{start=0,_end=6},{})
 assert(out[2].text:find('近7天 2 字',1,true),out[2].text)
end)
os.time,os.date=raw_time,raw_date
os.execute('rm -rf '..dir)
assert(ok,err)
print('PASS last seven local calendar dates remain seven across DST')
