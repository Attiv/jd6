-- Checked local runtime-file storage. No executable serialization or static dictionary cache.
local M = {}
local active, busy = nil, false
local serial = 0
local unpack_values = table.unpack or unpack
local function pack(...) return {n=select('#',...), ...} end
local function parent(path) return path:match('^(.*)[/\\][^/\\]+$') or '.' end
local function join(dir,name) return dir .. '/' .. name end
local function home(dir)
    if dir then return dir end
    return rime_api and rime_api.get_user_data_dir() or '.'
end
local function unique(path)
    serial = serial + 1
    return path .. '.tmp.' .. tostring(os.time()) .. '.' .. tostring({}):gsub('[^%w]','') .. '.' .. serial
end
local function raw_read(path)
    local f,err,code = io.open(path,'rb')
    if not f and code==2 then
        -- A Windows process may have stopped between its two replacement renames.
        local parked=path..'.replace-old'
        local saved,saved_err,saved_code=io.open(parked,'rb')
        if saved then
            local closed,close_err=saved:close()
            if not closed then return nil,close_err end
            local restored,restore_err=os.rename(parked,path)
            if not restored then return nil,'原文件保留于 '..parked..'：'..tostring(restore_err) end
            f,err,code=io.open(path,'rb')
        elseif saved_code~=2 then return nil,saved_err end
    end
    if not f then
        if code == 2 then return false end -- missing is distinct from unreadable
        return nil,err or '无法读取文件'
    end
    local data,read_err = f:read('*a')
    local ok,close_err = f:close()
    if not data or not ok then return nil,read_err or close_err or '读取文件失败' end
    return data
end
local function checked_temp(path,data)
    local tmp = unique(path)
    local f,err = io.open(tmp,'wb')
    if not f then return nil,err end
    local ok,write_err = f:write(data)
    local closed,close_err = f:close()
    if not ok or not closed then os.remove(tmp); return nil,write_err or close_err or '写入失败' end
    return tmp
end
local function replace(tmp,path)
    local ok,err = os.rename(tmp,path)
    if ok then return true end
    if (package.config or '/'):sub(1,1) ~= '\\' then os.remove(tmp); return false,err end
    -- MSVCRT rename cannot replace an existing destination. Never unlink the original.
    local existing,read_err = raw_read(path)
    if existing == nil then os.remove(tmp); return false,read_err end
    if existing == false then os.remove(tmp); return false,err end
    local parked = path .. '.replace-old'
    local stale,stale_err=raw_read(parked)
    if stale==nil then os.remove(tmp); return false,stale_err end
    if stale~=false then
        local removed,remove_err=os.remove(parked)
        if not removed then os.remove(tmp); return false,remove_err end
    end
    local moved = os.rename(path,parked)
    if not moved then os.remove(tmp); return false,err end
    ok,err = os.rename(tmp,path)
    if not ok then
        local restored,restore_err = os.rename(parked,path)
        os.remove(tmp)
        return false, restored and err or ('原文件保留于 '..parked..'：'..tostring(restore_err))
    end
    os.remove(parked)
    return true
end
local function atomic(path,data,backup)
    local before,err = raw_read(path)
    if before == nil then return false,err end
    if data == false then
        if before == false then return true end
        local ok,e=os.remove(path); return ok == true,e
    end
    local tmp; tmp,err=checked_temp(path,data)
    if not tmp then return false,err end
    if backup and before ~= false then
        local bt; bt,err=checked_temp(path..'.bak',before)
        if not bt then os.remove(tmp); return false,err end
        local ok; ok,err=replace(bt,path..'.bak')
        if not ok then os.remove(tmp); return false,err end
    end
    return replace(tmp,path)
end
local function hex(s) return (s:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
local function unhex(s)
    if not s or #s%2~=0 or s:find('[^%da-f]') then return nil end
    return (s:gsub('..',function(c) return string.char(tonumber(c,16)) end))
end
local function fields(line)
    local out={}; for v in (line..'\t'):gmatch('(.-)\t') do out[#out+1]=v end; return out
end
local function lines(data)
    local out={}
    if not data or data=='' then return out end
    for line in ((data or '') .. ((data or ''):sub(-1)=='\n' and '' or '\n')):gmatch('(.-)\n') do out[#out+1]=line end
    return out
end
local function content(ls) return #ls>0 and table.concat(ls,'\n')..'\n' or '' end
local function identity(line,kind)
    if kind=='orders' then
        -- Lazy reuse avoids a module initialization cycle and keeps legacy space/CRLF parsing identical.
        local rec=require('xmjd6.candidate_order_core').parse_line(line,0)
        if not rec then return nil end
        return table.concat({rec.promoted,rec.old_code,rec.displaced,rec.target_code,rec.new_code or ''},"\t"),rec.target_code
    end
    if line:match('^%s*#') then return nil end
    local text,code=line:match('^(.-)\t([^\t]+)')
    if not text then return nil end
    text=text:match('^%s*(.-)%s*$'); code=code:match('^%s*(.-)%s*$')
    if text=='' or code=='' then return nil end
    local id=text.."\t"..code
    return id,id
end
local function key(line,kind) local _,k=identity(line,kind); return k end
local function delta(before,after,kind,path)
    local old,new=lines(before or ''),lines(after or '')
    local function unmatched(a,b)
        local counts={}
        for _,s in ipairs(b) do local id=identity(s,kind); if id then counts[id]=(counts[id] or 0)+1 end end
        local result={}
        for i,s in ipairs(a) do
            local id=identity(s,kind)
            if id then
                if (counts[id] or 0)>0 then counts[id]=counts[id]-1
                else result[#result+1]={line=s,index=i} end
            end
        end
        return result
    end
    return {path=path,kind=kind,removed=unmatched(old,new),added=unmatched(new,old)}
end
local function encode_history(items,dir)
    local out={'XMJD6_UNDO_1'..'\t'..hex(dir)}
    for _,h in ipairs(items) do
        out[#out+1]=table.concat({'H',hex(h.id),hex(h.label),h.time},'\t')
        for _,f in ipairs(h.files) do
            out[#out+1]=table.concat({'F',hex(f.path),f.kind},'\t')
            for _,v in ipairs(f.removed) do out[#out+1]=table.concat({'D',v.index,hex(v.line)},'\t') end
            for _,v in ipairs(f.added) do out[#out+1]=table.concat({'A',v.index,hex(v.line)},'\t') end
            out[#out+1]='E'
        end
        out[#out+1]='X'
    end
    return content(out)
end
local function decode_history(data,dir)
    if data==false then return {} end
    local ls=lines(data); local header=fields(table.remove(ls,1) or '')
    if header[1]~='XMJD6_UNDO_1' or not unhex(header[2]) then return nil,'恢复记录格式无效' end
    if unhex(header[2])~=dir then return nil,'恢复日志来自其他目录',true end
    local items,h,f={},nil,nil
    for _,line in ipairs(ls) do
        local p=fields(line)
        if p[1]=='H' and not h then
            local id,label=unhex(p[2]),unhex(p[3]); local time=tonumber(p[4])
            if not id or not label or not time then return nil,'恢复记录损坏' end
            h={id=id,label=label,time=time,files={}}
        elseif p[1]=='F' and h and not f then
            local path=unhex(p[2]); if not path or parent(path)~=dir or (p[3]~='phrases' and p[3]~='orders') then return nil,'恢复文件路径无效' end
            f={path=path,kind=p[3],removed={},added={}}
        elseif (p[1]=='D' or p[1]=='A') and f then
            local index,line_value=tonumber(p[2]),unhex(p[3])
            if not index or index<1 or index%1~=0 or not line_value or not identity(line_value,f.kind) then return nil,'恢复条目无效' end
            local bucket=p[1]=='D' and f.removed or f.added
            bucket[#bucket+1]={index=index,line=line_value}
        elseif p[1]=='E' and h and f then h.files[#h.files+1]=f; f=nil
        elseif p[1]=='X' and h and not f then items[#items+1]=h; h=nil
        else return nil,'恢复记录不完整' end
    end
    if h or f then return nil,'恢复记录不完整' end
    return items
end
local function history_path(dir) return join(dir,'runtime_undo.tsv') end
local function txn_path(dir) return join(dir,'runtime_tools.transaction') end
local function encode_txn(files,dir)
    local out={'XMJD6_TXN_1'..'\t'..hex(dir)}
    for _,f in ipairs(files) do
        out[#out+1]=table.concat({'F',hex(f.path),f.before==false and '-' or hex(f.before),f.after==false and '-' or hex(f.after)},'\t')
    end
    return content(out)
end
local function decode_txn(data,dir)
    local ls=lines(data); local header=fields(table.remove(ls,1) or '')
    if header[1]~='XMJD6_TXN_1' or not unhex(header[2]) then return nil,'事务记录格式无效' end
    if unhex(header[2])~=dir then return nil,'事务来自其他目录',true end
    local out,seen={},{}
    for _,s in ipairs(ls) do
        local p=fields(s); local path=unhex(p[2])
        if p[1]~='F' or not path or parent(path)~=dir or path==txn_path(dir) or seen[path] then return nil,'事务文件路径无效' end
        local before,after=unhex(p[3]),unhex(p[4])
        if p[3]=='-' then before=false end; if p[4]=='-' then after=false end
        if before==nil or after==nil then return nil,'事务记录损坏' end
        seen[path]=true; out[#out+1]={path=path,before=before,after=after}
    end
    return out
end
local function quarantine(path,data)
    local ok,err=atomic(path..'.foreign.bak',data,true)
    if not ok then return false,err end
    ok,err=os.remove(path)
    return ok==true,err
end
local function read_history(dir)
    local path=history_path(dir)
    local data,err=raw_read(path); if data==nil then return nil,nil,err end
    local items,parse_err,foreign=decode_history(data,dir)
    if foreign then
        local ok; ok,err=quarantine(path,data)
        if not ok then return nil,nil,err end
        return {},false
    end
    return items,data,parse_err
end
function M.recover(dir)
    if busy or active then return true end
    dir=home(dir)
    local data,err=raw_read(txn_path(dir)); if data==false then return true end
    if not data then return false,err end
    local files,foreign; files,err,foreign=decode_txn(data,dir)
    if foreign then return quarantine(txn_path(dir),data) end
    if not files then return false,err end
    for _,f in ipairs(files) do
        local current,e=raw_read(f.path)
        if current==nil then return false,e end
        if current~=f.before and current~=f.after then return false,'未完成事务与外部修改冲突：'..f.path end
    end
    busy=true
    for _,f in ipairs(files) do
        local ok; ok,err=atomic(f.path,f.after,true)
        if not ok then busy=false; return false,err end
    end
    busy=false
    local ok; ok,err=os.remove(txn_path(dir)); return ok==true,err
end
function M.read(path)
    if active and active.by_path[path] then return active.by_path[path].after end
    if not busy and not active then local ok,err=M.recover(parent(path)); if not ok then return nil,err end end
    return raw_read(path)
end
function M.write(path,data)
    if active then
        local f=active.by_path[path]
        if not f then return false,'事务未声明文件：'..path end
        f.after=data; return true
    end
    local ok,err=M.recover(parent(path)); if not ok then return false,err end
    return atomic(path,data,true)
end
-- Small runtime stores only; this adapter lets existing parsers read staged data.
function M.open(path,mode)
    if mode=='r' then
        local data,err=M.read(path)
        if data==false then return nil,'文件不存在',2 end
        if not data then return nil,err end
        return {lines=function()
            local ls,i=lines(data),0
            return function() i=i+1; return ls[i] end
        end,close=function() return true end}
    end
    local chunks={}
    if mode=='a' then
        local data,err=M.read(path); if data==nil then return nil,err end
        if data then chunks[1]=data end
    end
    return {write=function(self,...)
        for i=1,select('#',...) do chunks[#chunks+1]=tostring(select(i,...)) end
        return self
    end,close=function() return M.write(path,table.concat(chunks)) end}
end
local function commit(files,dir)
    -- Optimistic validation: reject edits made since this operation began.
    for _,f in ipairs(files) do
        local current,err=raw_read(f.path)
        if current==nil then return false,err end
        if current~=f.before then return false,'文件已被外部修改，请重试：'..f.path end
    end
    local ok,err=atomic(txn_path(dir),encode_txn(files,dir),false)
    if not ok then return false,err end
    busy=true
    for i,f in ipairs(files) do
        ok,err=atomic(f.path,f.after,true)
        if not ok then
            local rolled=true
            for j=i,1,-1 do
                local current=raw_read(files[j].path)
                if current~=files[j].before then
                    local restored=atomic(files[j].path,files[j].before,false)
                    rolled=rolled and restored
                end
            end
            busy=false
            if rolled then os.remove(txn_path(dir)) end
            return false,(err or '保存失败') .. (rolled and '' or '；已保留未完成事务，下次访问将尝试恢复')
        end
    end
    busy=false
    ok,err=os.remove(txn_path(dir))
    if not ok then return false,err or '事务清理失败，下次访问将恢复' end
    return true
end
function M.history(dir,query)
    dir=home(dir)
    local ok,err=M.recover(dir); if not ok then return nil,err end
    local items,_,read_err=read_history(dir); if not items then return nil,read_err end
    local out={}; query=(query or ''):lower()
    for i=#items,1,-1 do
        local entry=items[i]
        local matches=query=='' or entry.label:lower():find(query,1,true)
        if not matches then
            for _,f in ipairs(entry.files) do
                for _,bucket in ipairs({f.removed,f.added}) do
                    for _,v in ipairs(bucket) do if v.line:lower():find(query,1,true) then matches=true end end
                end
            end
        end
        if matches then out[#out+1]=entry end
    end
    return out
end
function M.perform(label,specs,fn,remember)
    if active then return fn() end
    local dir=parent(specs[1].path)
    local ok,err=M.recover(dir); if not ok then return false,err end
    local tx={by_path={},files={}}
    for _,spec in ipairs(specs) do
        if parent(spec.path)~=dir then return false,'事务文件必须在同一目录' end
        if not tx.by_path[spec.path] then
            local before; before,err=raw_read(spec.path); if before==nil then return false,err end
            local f={path=spec.path,kind=spec.kind,before=before,after=before}
            tx.files[#tx.files+1]=f; tx.by_path[spec.path]=f
        end
    end
    active=tx
    local result=pack(pcall(fn)); active=nil
    if not result[1] then return false,tostring(result[2]) end
    if not result[2] then return unpack_values(result,2,result.n) end
    local changed,entry={}, {id=unique('op'),label=label,time=os.time(),files={}}
    for _,f in ipairs(tx.files) do
        if f.before~=f.after then
            changed[#changed+1]=f
            local d=delta(f.before,f.after,f.kind,f.path)
            if #d.removed+#d.added>0 then entry.files[#entry.files+1]=d end
        end
    end
    if #changed==0 then return unpack_values(result,2,result.n) end
    if remember and #entry.files>0 then
        local hp=history_path(dir)
        local items,before,read_err=read_history(dir); if not items then return false,read_err end
        items[#items+1]=entry; while #items>20 do table.remove(items,1) end
        changed[#changed+1]={path=hp,before=before,after=encode_history(items,dir)}
    end
    ok,err=commit(changed,dir)
    if not ok then return false,err end
    return unpack_values(result,2,result.n)
end
local function inverse(file,current)
    local ls=lines(current or '')
    if file.kind=='orders' then
        local touched,known={},{}
        for _,bucket in ipairs({file.added,file.removed}) do
            for _,v in ipairs(bucket) do touched[key(v.line,file.kind)]=true; known[identity(v.line,file.kind)]=true end
        end
        for _,line in ipairs(ls) do
            local id=identity(line,file.kind)
            if id and touched[key(line,file.kind)] and not known[id] then
                return nil,'同一编码已有其他调频，无法安全恢复'
            end
        end
    end
    for _,v in ipairs(file.added) do
        local found
        for i,s in ipairs(ls) do if identity(s,file.kind)==identity(v.line,file.kind) then found=i; break end end
        if not found then return nil,'记录已被修改，无法安全撤销' end
        table.remove(ls,found)
    end
    for _,v in ipairs(file.removed) do
        local exists=false
        for _,s in ipairs(ls) do
            if identity(s,file.kind)==identity(v.line,file.kind) then exists=true
            elseif identity(s,file.kind) and key(s,file.kind)==key(v.line,file.kind) then return nil,'同一编码已有其他调频，无法安全恢复' end
        end
        if not exists then table.insert(ls,math.min(v.index,#ls+1),v.line) end
    end
    return content(ls)
end
function M.undo(id,dir)
    dir=home(dir)
    local ok,err=M.recover(dir); if not ok then return false,err end
    local hp=history_path(dir)
    local items,before,read_err=read_history(dir); if not items then return false,read_err end
    local index,entry
    for i,h in ipairs(items) do if h.id==id then index,entry=i,h; break end end
    if not entry then return false,'恢复记录已不存在' end
    local changes={}
    for _,f in ipairs(entry.files) do
        local current; current,err=raw_read(f.path); if current==nil then return false,err end
        local restored; restored,err=inverse(f,current)
        if not restored then return false,err end
        changes[#changes+1]={path=f.path,before=current,after=restored}
    end
    table.remove(items,index)
    changes[#changes+1]={path=hp,before=before,after=encode_history(items,dir)}
    ok,err=commit(changes,dir)
    return ok,ok and ('已恢复：'..entry.label) or err
end
return M
