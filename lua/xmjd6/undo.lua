-- Local record-level recovery. Management candidates are never actions by themselves.
local store=require('xmjd6.runtime_store')
local M={}
_G.__runtime_undo_state=_G.__runtime_undo_state or {}
local state=_G.__runtime_undo_state
local function query(input) return (input or ''):match('^=undo(.*)$') end
local function refresh(ctx)
    if type(ctx.refresh_non_confirmed_composition)=='function' then
        pcall(function() ctx:refresh_non_confirmed_composition() end)
    end
end
local function candidate(seg,kind,text,comment,quality)
    local c=Candidate(kind,seg.start,seg._end,text,comment or '')
    c.quality=quality or 600000; yield(c)
end
local function find(id)
    local history,err=store.history()
    if not history then return nil,err end
    for _,entry in ipairs(history) do if entry.id==id then return entry end end
    return nil,'恢复记录已不存在'
end
function M.translator(input,seg,env)
    local filter=query(input); if filter==nil then return end
    if state.pending and state.pending.input==input then
        local entry=state.pending.entry
        candidate(seg,'runtime_undo_confirm','确认恢复：'..entry.label,'再按0执行，其他键取消',700000)
        local shown=0
        for _,f in ipairs(entry.files) do
            for _,v in ipairs(f.removed) do
                shown=shown+1
                if shown<=10 then candidate(seg,'runtime_undo_preview','恢复：'..v.line:gsub('\t',' / '),'本次操作之前的记录',690000-shown) end
            end
            for _,v in ipairs(f.added) do
                shown=shown+1
                if shown<=10 then candidate(seg,'runtime_undo_preview','撤销：'..v.line:gsub('\t',' / '),'本次操作新增的记录',690000-shown) end
            end
        end
        if shown>10 then candidate(seg,'runtime_undo_preview','共影响'..shown..'条记录','预览仅展示前10条',680000) end
        return
    end
    if state.notice and state.notice.input==input then
        candidate(seg,'runtime_undo_notice',state.notice.message,'本机操作恢复',700000)
    end
    local history,err=store.history(nil,filter)
    if not history then candidate(seg,'runtime_undo_error','无法读取恢复记录',err); return end
    if #history==0 then
        candidate(seg,'runtime_undo_empty',filter=='' and '暂无可恢复操作' or '没有匹配的恢复记录','仅记录启用后最近20次本机删除/调频操作')
        return
    end
    for i,h in ipairs(history) do
        candidate(seg,'runtime_undo',h.label,os.date('%m-%d %H:%M',h.time)..'〔恢复·'..h.id..'〕',600000-i)
    end
end
function M.processor(key,env)
    if not key or key:release() or key:ctrl() or key:alt() or key:super() then return 2 end
    local ctx=env and env.engine and env.engine.context; if not ctx then return 2 end
    local input=ctx.input or ''; local zero=key.keycode==48
    if state.pending and state.pending.input~=input then
        state.pending=nil; refresh(ctx)
        if zero then return 1 end
    end
    if state.notice and state.notice.input~=input then state.notice=nil end
    if query(input)==nil then return 2 end
    if not zero then
        if state.pending or state.notice then state.pending=nil; state.notice=nil; refresh(ctx) end
        -- Prevent helper text from being submitted through normal keyboard confirmation.
        if key.keycode==32 or key.keycode==13 or key.keycode==10
            or (key.keycode>=49 and key.keycode<=57) then return 1 end
        return 2
    end
    if state.pending then
        local id=state.pending.entry.id; state.pending=nil
        local ok,message=store.undo(id)
        state.notice={input=input,message=ok and message or ('恢复失败：'..tostring(message))}
        refresh(ctx); return 1
    end
    local ok,c=pcall(function() return ctx:get_selected_candidate() end)
    if ok and c and c.type=='runtime_undo' then
        local id=(c.comment or ''):match('〔恢复·(.-)〕$')
        local entry,err=find(id)
        if entry then state.pending={input=input,entry=entry}; state.notice=nil
        else state.notice={input=input,message=err} end
        refresh(ctx)
    end
    return 1
end
return M
