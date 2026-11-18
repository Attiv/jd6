-- Explicit, read-only code inspection. Never scan large dictionaries on ordinary keystrokes.
local core=require('xmjd6.candidate_order_core')
local dynamic=require('xmjd6.dynamic_phrase_core')
local store=require('xmjd6.runtime_store')
local topup=require('xmjd6.xmjd6_topup_processor')
local M={}
local states=setmetatable({}, {__mode='k'})
local function set(value)
    local out={}; for i=1,#value do out[value:sub(i,i)]=true end; return out
end
local function read_config(env,method,path,default)
    local config=env and env.engine and env.engine.schema and env.engine.schema.config
    if config and type(config[method])=='function' then
        local ok,v=pcall(function() return config[method](config,path) end)
        if ok and v~=nil then return v end
    end
    return default
end
local function options(env)
    local o={dir=rime_api.get_user_data_dir()}
    o.enabled=read_config(env,'get_bool','topup/enabled',true)
    o.topup_set=set(read_config(env,'get_string','topup/topup_with',''))
    o.alphabet=set(read_config(env,'get_string','speller/alphabet',"abcdefghijklmnopqrstuvwxyz"))
    o.topup_min=math.max(1,read_config(env,'get_int','topup/min_length',4))
    o.topup_min_danzi=math.max(1,read_config(env,'get_int','topup/min_length_danzi',o.topup_min))
    o.topup_max=math.max(o.topup_min,read_config(env,'get_int','topup/max_length',6))
    o.topup_command=read_config(env,'get_bool','topup/topup_command',false)
    o.protected_codes=require('xmjd6.protected_codes').load()
    o.order_enabled=core.is_enabled(env)
    o.dynamic_file=read_config(env,'get_string','dynamic_phrase/store_file','dynamic_phrases.txt')
    o.master_dict=read_config(env,'get_string','translator/dictionary','xmjd6.extended')
    o.order_file=read_config(env,'get_string','candidate_order/store_file',core.default_filename)
    local ctx=env and env.engine and env.engine.context
    if ctx and type(ctx.get_option)=='function' then o.danzi=ctx:get_option('danzi_mode') end
    return o
end
function M.topup_point(code,o)
    o=o or options()
    if o.enabled==false then return nil end
    for i=2,#code do
        local input,key=code:sub(1,i-1),code:sub(i,i)
        local prefix=code:sub(1,i)
        if (not o.alphabet or o.alphabet[key]) and not (o.protected_codes or {})[prefix]
            and not (o.topup_command and o.topup_set[code:sub(1,1)])
            and (o.order_enabled==false or not core.has_code_prefix(prefix))
            and topup.should_topup(input,key,o,o.danzi) then return i end
    end
end
-- Fail closed on structures outside this deliberately small dictionary-header subset.
-- The shipped master encoder is accepted literally; implicit/generated codes are not scanned.
local HEADER_KEYS={name=true,version=true,sort=true,use_preset_vocabulary=true}
local ENCODER_LINES={
    {2,'rules:'}, {4,'-length_equal:2'}, {6,'formula:"AaAbBaBb"'},
    {4,'-length_equal:3'}, {6,'formula:"AaBaCaAc"'},
    {4,'-length_in_range:[4,99]'}, {6,'formula:"AaBaCaZa"'},
}
local function simple_list_item(body)
    return body:match('^%-%s+([%w_%.%-]+)$')
        or body:match('^%-%s+"([%w_%.%-]+)"$')
        or body:match("^%-%s+'([%w_%.%-]+)'$")
end
local function inspect_header(file,allow_encoder)
    local result={imports={},supported=true,has_imports=false,has_data=false}
    local mode,columns,encoder,in_data
    local function finish_encoder()
        if not encoder then return end
        if #encoder~=#ENCODER_LINES then result.supported=false end
        for i,item in ipairs(encoder) do
            local expected=ENCODER_LINES[i]
            if not expected or item[1]~=expected[1] or item[2]~=expected[2] then result.supported=false end
        end
        encoder=nil; mode=nil
    end
    local function inspect_row(line)
        result.has_data=true
        -- Same explicit-code grammar as the occupancy scanner. Empty codes may be auto-encoded
        -- by Rime, and malformed/implicit rows must never yield a free-code guarantee.
        local code=line:match('^[^\t]+\t([^%s〔#]+)')
        -- Numeric spellings can derive lowercase codes (the default schema strips trailing digits).
        if not code or code:find('%d') then result.supported=false end
    end
    for line in file:lines() do
        line=line:gsub('^'..string.char(239,187,191),'')
        local body=line:match('^%s*(.-)%s*$')
        if body~='' and body:sub(1,1)~='#' then
            if body=='...' then finish_encoder(); in_data=true
            elseif in_data then inspect_row(line)
            elseif not line:match('^[^\t]*:') and line:match('^[^\t]+\t[a-z]+') then
                finish_encoder(); in_data=true; inspect_row(line)
            elseif body~='---' then
                body=body:gsub('%s+#.*$','')
                if mode=='encoder' and line:match('^%s') then
                    local indent=line:match('^( *)')
                    encoder[#encoder+1]={#indent,(body:gsub('%s+',''))}
                else
                    finish_encoder()
                    local key,value=body:match('^([A-Za-z_][A-Za-z_0-9]*)%s*:%s*(.-)%s*$')
                    if key then
                        mode=nil
                        if key=='import_tables' then
                            result.has_imports=true
                            if value=='' then mode='imports' else result.supported=false end
                        elseif key=='columns' then
                            columns={}
                            if value=='' then mode='columns' else result.supported=false end
                        elseif key=='encoder' and allow_encoder and value=='' and line:sub(1,1)=='e' then
                            mode='encoder'; encoder={}
                        elseif not HEADER_KEYS[key] then result.supported=false end
                    elseif mode=='imports' then
                        local name=simple_list_item(body)
                        if name then result.imports[#result.imports+1]=name else result.supported=false end
                    elseif mode=='columns' then
                        local name=simple_list_item(body)
                        if name then columns[#columns+1]=name else result.supported=false end
                    else result.supported=false end
                end
            end
        end
    end
    finish_encoder()
    if columns and (columns[1]~='text' or columns[2]~='code') then result.supported=false end
    return result
end
function M.inspect(text,code,o)
    o=o or options(); local dir=o.dir or rime_api.get_user_data_dir()
    if type(code)~='string' or not code:match('^[a-z]+$') or #code>32 then return nil,'仅预览1～32位小写字母键道码' end
    text=tostring(text or '')
    if not utf8.len(text) then return nil,'词条不是有效UTF-8' end
    local full=text~='' and core.full_code_for_phrase(text,code,dir) or nil
    local candidates=core.candidate_new_codes(code,full)
    local wanted={[code]=true}; for _,c in ipairs(candidates) do wanted[c]=true end
    local missing,known={},{}
    for _,name in ipairs(core.occupied_dict_files) do
        known[name:gsub("%.dict%.yaml$","")]=true
        local file=io.open(dir..'/'..name,'r')
        if not file then missing[#missing+1]=name
        else
            local header=inspect_header(file); file:close()
            if not header.supported or header.has_imports then
                missing[#missing+1]='无法验证子词表头部/编码/导入：'..name
            end
        end
    end
    local master=o.master_dict or 'xmjd6.extended'
    local file=io.open(dir..'/'..master..'.dict.yaml','r')
    if not file then missing[#missing+1]='主词库清单：'..master
    else
        local header=inspect_header(file,true); file:close()
        if not header.supported or not header.has_imports then missing[#missing+1]='无法验证主词库导入清单' end
        for _,name in ipairs(header.imports) do
            if not known[name] then missing[#missing+1]='未覆盖导入：'..name end
        end
        -- Master-owned data is outside the fixed source-table scanner.
        if header.has_data then missing[#missing+1]='主词库含额外数据：'..master end
    end
    if master~='xmjd6.extended' then missing[#missing+1]='非默认主词库：'..master end
    local order_path=dir..'/'..(o.order_file or core.default_filename)
    local runtime_paths={dir..'/'..(o.dynamic_file or 'dynamic_phrases.txt')}
    if o.order_enabled~=false then runtime_paths[#runtime_paths+1]=order_path end
    for _,path in ipairs(runtime_paths) do
        local data,err=store.read(path); if data==nil then return nil,err end
    end
    local occupied,errors=core.preview_occupancy(dir,wanted,order_path,o)
    local available={}; local complete=#missing==0 and #errors==0
    if complete then
        for _,c in ipairs(candidates) do if core.code_available(occupied,c) then available[#available+1]=c end end
    end
    if not o.topup_set then
        local defaults=options(); for k,v in pairs(defaults) do if o[k]==nil then o[k]=v end end
    end
    return {code=code,text=text,full_code=full,occupants=occupied,available=available,
        complete=complete,missing=missing,errors=errors,topup_point=M.topup_point(code,o)}
end
local function is_add_command(input)
    return input:match('^=add/')~=nil
end
local function history()
    local state=_G.__dynamic_phrase_state or {}
    return state.commit_history or (state.last_commit_text and {state.last_commit_text}) or {}
end
local function refresh(ctx)
    if type(ctx.refresh_non_confirmed_composition)=='function' then pcall(function() ctx:refresh_non_confirmed_composition() end) end
end
function M.processor(key,env)
    if not key or key:release() or key:ctrl() or key:alt() or key:super() then return 2 end
    local ctx=env and env.engine and env.engine.context; if not ctx then return 2 end
    local input=ctx.input or ''
    if not is_add_command(input) then states[ctx]=nil; return 2 end
    if key.keycode==0xff09 then
        local cmd=dynamic.resolve_command(input,history())
        if not cmd or cmd.action~='add' then return 2 end
        local result,err=M.inspect(cmd.text,cmd.code,options(env))
        states[ctx]={input=input,result=result,error=err}; refresh(ctx); return 1
    end
    if states[ctx] and states[ctx].input~=input then states[ctx]=nil end
    return 2
end
local function emit(seg,text,comment,quality)
    local c=Candidate('code_preview',seg.start,seg._end,text,comment or '')
    c.quality=quality or 550000; yield(c)
end
function M.translator(input,seg,env)
    if not is_add_command(input) then return end
    local ctx=env and env.engine and env.engine.context
    local state=ctx and states[ctx]
    if not state or state.input~=input then return end
    if not state.result then emit(seg,'无法检查码位',state.error); return end
    local r=state.result
    emit(seg,'码位 '..r.code,r.complete and '源词表检查完成；部署版本可能不同，不自动挪码' or '检查不完整，不保证空码（词库/编码/调频记录需核对）',560000)
    local texts={}; for text in pairs(r.occupants[r.code] or {}) do texts[#texts+1]=text end; table.sort(texts)
    if #texts==0 then emit(seg,'未发现占用',r.complete and '所查源词表与运行时记录中无占用' or '不保证空码') end
    for i,text in ipairs(texts) do if i<=10 then emit(seg,text,'该码占用词条（不代表候选顺序）',550000-i) end end
    if #texts>10 then emit(seg,'共'..#texts..'个占用词条','仅展示前10条') end
    if r.topup_point then emit(seg,'顶功风险：第'..r.topup_point..'键前可能上屏','按当前顶功规则估计；前端或其他processor仍可能影响输入') end
    for _,code in ipairs(r.available) do emit(seg,'可用补码：'..code,'按词的全码规则推导；不会自动修改编码') end
    if not r.full_code then emit(seg,'未推导出完整词码','仅列占用，不给出猜测补码') end
    emit(seg,'确认添加仍按 ; / 空格 / 回车','保留原造词方式；Tab可重新检查')
end
require('xmjd6.mem_cleaner').register(function() states=setmetatable({}, {__mode='k'}) end)
return M
