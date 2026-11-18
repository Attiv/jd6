-- Gregorian calendar-day arithmetic. No timestamp +/-86400 or DST assumptions.
local M = {}
local MONTHS = {31,28,31,30,31,30,31,31,30,31,30,31}
local function leap(y) return y%4==0 and (y%100~=0 or y%400==0) end
local function month_days(y,m) return m==2 and leap(y) and 29 or MONTHS[m] end
local function year_start(y)
    local n=y-1
    return 365*n+math.floor(n/4)-math.floor(n/100)+math.floor(n/400)
end
function M.parse(value)
    if type(value)~='string' then return nil,'日期应为8位 YYYYMMDD' end
    local y,m,d=value:match('^(%d%d%d%d)(%d%d)(%d%d)$')
    y,m,d=tonumber(y),tonumber(m),tonumber(d)
    if not y or y<1 or m<1 or m>12 or d<1 or d>month_days(y,m) then return nil,'无效公历日期：'..value end
    local serial=year_start(y)+d
    for i=1,m-1 do serial=serial+month_days(y,i) end
    return {year=y,month=m,day=d,serial=serial}
end
function M.from_serial(serial)
    if type(serial)~='number' or serial%1~=0 or serial<1 or serial>year_start(10000) then
        return nil,'结果超出公历0001～9999年范围'
    end
    local lo,hi=1,9999
    while lo<hi do
        local mid=math.floor((lo+hi+1)/2)
        if year_start(mid)<serial then lo=mid else hi=mid-1 end
    end
    local day,month=serial-year_start(lo),1
    while day>month_days(lo,month) do day=day-month_days(lo,month); month=month+1 end
    return string.format('%04d-%02d-%02d',lo,month,day)
end
function M.add(value,days)
    local date,err=M.parse(value); if not date then return nil,err end
    if type(days)~='number' or days%1~=0 then return nil,'天数必须为整数' end
    return M.from_serial(date.serial+days)
end
function M.difference(first,last)
    local a,err=M.parse(first); if not a then return nil,err end
    local b; b,err=M.parse(last); if not b then return nil,err end
    return b.serial-a.serial
end
function M.week(value)
    local date,err=M.parse(value); if not date then return nil,err end
    local start=date.serial-(date.serial-1)%7
    local first; first,err=M.from_serial(start); if not first then return nil,err end
    local last; last,err=M.from_serial(start+6); if not last then return nil,err end
    return first,last
end
local function today() return os.date('%Y%m%d') end
local function emit(seg,kind,text,comment)
    local c=Candidate(kind,seg.start,seg._end,text,comment or '')
    c.quality=450000; yield(c)
end
function M.translator(input,seg,env)
    local value,sign,count,unit=input:match('^=(%d%d%d%d%d%d%d%d)([+-])(%d+)([dDwW])$')
    if not value then
        sign,count,unit=input:match('^=today([+-])(%d+)([dDwW])$')
        if sign then value=today() end
    end
    if value then
        local days=tonumber(count)
        if not days or days>3660000 then emit(seg,'date_tools_error','日期偏移过大','最多3660000天'); return end
        days=days*(unit:lower()=='w' and 7 or 1)*(sign=='-' and -1 or 1)
        local result,err=M.add(value,days)
        emit(seg,result and 'date_tools' or 'date_tools_error',result or err,'公历加减；d=天，w=7天，不含节假日规则')
        return
    end
    local first,last=input:match('^=diff/(%d%d%d%d%d%d%d%d)/(%d%d%d%d%d%d%d%d)$')
    if first then
        local n,err=M.difference(first,last)
        emit(seg,n and 'date_tools' or 'date_tools_error',n and (n..'天') or err,'后一个日期减前一个日期，不含起始日')
        return
    end
    if input=='=week' then
        local a,b=M.week(today())
        if not a then emit(seg,'date_tools_error',b); return end
        emit(seg,'date_tools',a..' ～ '..b,'本周范围：周一至周日')
        emit(seg,'date_tools',a,'本周一')
        emit(seg,'date_tools',b,'本周日')
    end
end
return M
