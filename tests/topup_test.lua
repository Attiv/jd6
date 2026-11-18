package.path='./lua/?.lua;'..package.path
local processor=require('xmjd6.xmjd6_topup_processor')
local env={enabled=false,engine={context=setmetatable({}, {__index=function() error('disabled topup accessed context') end})}}
local key={keycode=97,release=function() return false end,ctrl=function() return false end,alt=function() return false end}
assert(processor.func(key,env)==2,'disabled topup must pass through without touching context')
print('PASS named topup switch disables topup without positional processor removal')
