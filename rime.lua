--[[
librime-lua 样例
```
  engine:
    translators:
      - lua_translator@lua_function3
      - lua_translator@lua_function4
    filters:
      - lua_filter@lua_function1
      - lua_filter@lua_function2
```
其中各 `lua_function` 为在本文件所定义变量名。
--]]

--[[
本文件的后面是若干个例子，按照由简单到复杂的顺序示例了 librime-lua 的用法。
每个例子都被组织在 `lua` 目录下的单独文件中，打开对应文件可看到实现和注解。

各例可使用 `require` 引入。
```
  foo = require("bar")
```
可认为是载入 `lua/bar.lua` 中的例子，并起名为 `foo`。
配方文件中的引用方法为：`...@foo`。
--]]

-- date_translator: 将 `date` 翻译为当前日期
-- 详见 `lua/date.lua`:
date_translator = require("date")

-- time_translator: 将 `time` 翻译为当前时间
-- 详见 `lua/time.lua`
time_translator = require("time")



-- single_char_filter: 候选项重排序，使单字优先
-- 详见 `lua/single_char.lua`
-- single_char_filter = require("single_char")




-- 以词定字
-- 可在 default.yaml key_binder 下配置快捷键，默认为左右中括号 [ ]
select_character = require("xmjd6_select_character")
xmjd6_smart_2 = require("xmjd6_smart_2")
xmjd6_topup_processor = require("xmjd6_topup_processor")
--  | 替换为空格
add_space = require("add_space")
add_ge = require("add_ge")
bian_zi = require("bianzi")
-- 输入框显示候选
zimu_translator = require("zimu")
xmjd6_jisuanqi = require("xmjd6_jisuanqi")
xmjd6_shijian = require("xmjd6_shijian")
xmjd6_shuzi = require("xmjd6_shuzi")
unicode = require("unicode")
for_hint = require("for_hint")
xmjd6_embeded_cands = require("xmjd6_embeded_cands")
split = require("split")



local english = require("english")()
english_processor = english.processor
english_segmentor = english.segmentor
english_translator = english.translator
english_filter = english.filter
english_filter0 = english.filter0
binggan_completion = require("completion")