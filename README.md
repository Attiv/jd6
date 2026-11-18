# 星猫键道6 Rime 配置

## 命令搜索与操作恢复

- `=?` 查看全部功能；`=?stats` / `=?date` / `=?undo` 按命令、说明或别名筛选。
  日期也可用 `=?riqi`，统计可用 `=?tongji`；`=??` 仍是快符速查。
  帮助仅供查询，不会自动执行命令。
- `=undo` 查看最近 **20次本机**自造词删除和动态调频变更；`=undo关键词` 筛选。
  高亮记录后按一次 `0` 预览，再按一次 `0` 执行；其他普通按键取消确认。
  空格/回车和数字1～9不会执行恢复，也不会提交帮助文字；鼠标/触摸直接点击管理候选不是恢复操作。
- 删除自造词时清理的关联调频记录会一起恢复。恢复按记录进行，保留后来新增的无关词条；
  相关记录被改动或同一目标编码已有其他调频时拒绝恢复，原文件和恢复记录不变。
- 仅能恢复启用后的操作；直接编辑文件、外部同步、静态词库固化不属于本机操作历史。
  `runtime_undo.tsv` 是本机数据日志，不是上屏文字流水；现有 WebDAV 双文件同步无需修改。
  不要手工跨设备复制该日志或 `runtime_tools.transaction`；全目录备份应按原路径还原。
  若整目录复制到了其他路径，外来日志/事务会隔离为 `.foreign.bak`，本机重新建立历史，不执行外来的恢复操作。

### 码位预览（只读）

- 已输入完整 `=add/编码` 或 `=add/词/编码` 时，按 **Tab** 检查码位；原来的 `;` / 空格 / 回车添加方式不变。
- 面板列出源词表及运行时调频下的占用、顶功风险和按全码规则推导的空闲补码；不会自动改词库或挪码。
- 只在明确触发检查时扫描，不在普通打字或每个命令字母时扫描；大词库检查可能需要等待片刻。
  缺源词库、发现未覆盖/无法解析的导入、无编码/异常词条、含数字的派生码或未解析的调频补码时，显示“检查不完整”，不保证空码、不提供空闲补码建议。
  支持随项目提供的主词库 encoder 头部；只检查显式源编码和运行时记录，不检查编译版本、Rime 自动造词或用户学习词典。
  当前部分源表仍含缺编码/异常行，会保守显示不完整；只影响预览建议，不改变正常输入和造词。
  这是源配置快照，已部署词库可能不同；顶功提示也不替代前端真机验证。

### 文本加工增强

在现有 `/` / `=wrap` 面板中追加：去首尾空白、合并单行（折叠空白）、ASCII 全半角转换、
JSON 内容转义（不含外围引号）、UTF-8 URL 组件编码。原有包裹和大小写候选保持原顺序。
全半角仅转换 ASCII 对应的全角字符及全角空格，不改变中文标点或日文假名。

### 公历日期计算

| 输入 | 效果 |
|---|---|
| `=20261022+7d` | 2026-10-29 |
| `=20261022-2w` | 往前14天；w固定为7天 |
| `=today+7d` | 今天之后7个日历日 |
| `=diff/20261022/20261101` | 10天，后一个日期减前一个日期，不含起始日 |
| `=week` | 本周一至周日，以及两个端点日期 |

支持公历0001～9999年，验证闰年和无效日期；不使用“时间戳加86400秒”，不受夏令时长短日影响。
不计算法定假日或工作日。原 `=20261022` 日历查询、普通计算器和按位异或入口不变。

### 打字统计口径与本轮修复

`=stats` 中“键/汉字”沿用旧数据的 **中文模式可见ASCII总击键数 / 汉字上屏量**，
包括工具命令击键与生成文本上屏，不是精确中文编码码长；不反推或重写历史统计。
均速和峰速另外排除可识别的工具/历史复用输出；峰速仍为非重叠10秒窗口，不是滚动最佳10秒。
本轮修复自动保存遗漏进行中的均速样本、坏行覆盖有效数据/非法数值导致报表异常、
夏令时附近近7天范围不准确，并给无效行增加提示。详细审查结论见本地 `docs/plans/2026-10-22-stats-audit.md`。

### 运行时文件可靠性

`dynamic_phrases.txt`、`candidate_order.txt` 和 `typing_stats.txt` 保存前写临时文件、检查写入及关闭结果，
并保留上一次文件为同名 `.bak`。自造词/调频多文件变更带有本机事务记录，异常退出后下次访问尝试恢复；
遇到外部修改冲突则停止并提示，不强行覆盖。不要在输入法使用中删除未完成的事务记录。
POSIX 文件替换使用原子 rename；Windows 使用保留原文件的替换回退，不保证断电原子性。
与不遵守此协议的外部写入者之间采用保存前校验，不提供跨进程强锁。

热更新比较这两份小型运行时词表的实际内容，不依赖 `lfs`，同大小/同秒修改也能刷新；
没有建立或加载大词库分片索引，原编码、候选优先级及默认顶功行为不变。

流式输入改用 `xmjd6.custom.yaml` 中具名的 `topup/enabled: false`，
不再通过容易错位的 processor 序号删除组件。

本次更新 Lua/schema 后需重新部署一次；之后日常自造词、调频及恢复不用重新部署。

### 开发检查

安装 Lua 5.4（含 luac）、Python 3 和 PyYAML 后运行：

```bash
python3 tests/run_tests.py
```

测试文件纳入版本管理，所有数据读写测试使用独立临时目录，不访问真实个人词库。

## 常用脚本

### 调频(候选顺序)

- `scripts/apply_candidate_order.py` — 把 `candidate_order.txt`(Lua 运行时记录的调频)固化进 `xmjd6.candidate_order.dict.yaml`,并删除各词库中被挤走的旧条目。详见 `candidate_order_usage.md`

  ```bash
  python3 scripts/apply_candidate_order.py          # 默认 dry-run 预览
  python3 scripts/apply_candidate_order.py --apply  # 应用
  ```

### 自造词

- `scripts/promote_dynamic_phrases.py` — 把 `dynamic_phrases.txt` 里的自造词并入静态词库 `xmjd6.zidingyi.dict.yaml`,已入库的记录随之从动态文件移除

  ```bash
  python3 scripts/promote_dynamic_phrases.py
  ```

### 千问输入法同步

- `scripts/sync_qianwen_rime.sh` — 部署 `~/Library/Rime` 并备份、同步覆盖到千问输入法的预部署 Rime 包,再用官方 helper 重载

  ```bash
  scripts/sync_qianwen_rime.sh sync                 # 同步并重载
  scripts/sync_qianwen_rime.sh sync --with-runtime  # 连 candidate_order.txt / dynamic_phrases.txt 一起覆盖
  scripts/sync_qianwen_rime.sh sync --no-reload     # 只装文件不重载
  scripts/sync_qianwen_rime.sh status               # 千问更新后检查是否需要重新同步
  ```

  `scripts/qianwen_overlay/qime_trigger_compat.lua` 是同步时注入的按键兼容层。

  按键语义兼容引擎(`RimeSync/compat/libqime-key-semantics.dylib`)是旧版千问的厂商签名原件,无法为新版重建。
  当千问新版 `libqianwen_engine.dylib` 需要它没有的 ABI 符号时,脚本会打印警告并**跳过 libqime 替换**,
  Rime 数据照常同步。相关环境变量:

  ```bash
  QW_ENGINE_COMPAT_STRICT=1   # 兼容引擎不可用时直接中止(默认降级继续)
  QW_DISABLE_ENGINE_COMPAT=1  # 完全不用兼容引擎,也不再提示
  ```

- `scripts/rollback_qianwen.sh` — 用备份的千问 App 整包替换当前版本,并默认禁用自动更新

  ```bash
  scripts/rollback_qianwen.sh status            # 当前版本、可用备份、自动更新状态
  scripts/rollback_qianwen.sh install           # 装回默认的 1.1.5.23 备份
  scripts/rollback_qianwen.sh install <App 路径> # 装回指定版本(如换回新版)
  ```

  **千问 1.2.x 起不再把字母键交给 librime 的 processor 链**(只转发控制键和标点),
  顶功、`=` 引导键、`0` 调频、以词定字、快捷符号等全部 `lua_processor` 功能因此失效,
  且无法在 Lua 或 schema 层修复。1.1.5.23 是已知最后一个逐键处理版本。
  替换通过千问自带的厂商签名 `QianwenIMEAtomicSwap` helper 完成,替换前自动整包备份当前版本。

### 打包 / 多端同步

- `build.sh` — 全配置打包 `jd6.zip` 并拷到 iCloud(jd6_cang.zip);顺带把 `user.yaml` 的 tofu 置 true,打包前从 `trash/` 恢复 default.yaml
- `bbuild.sh` — 打包 `build/` 编译产物为 `jd6_build.zip` → iCloud
- `irime.sh` — 打包成 iRime 目录结构 → iCloud(jd6_irime.schema.zip)
- `fc5.sh` — rsync 整个配置到 fcitx5 目录(`~/.local/share/fcitx5/rime`)

### 词库优化

- `shrink_empty_codes.py` — 安全缩码:仅当"短一位的码"在全库为空时才缩,默认 dry-run 出报告,`--apply` 生效,保护名单 `shrink_empty_codes_protect.txt`。详见 `shrink_empty_codes_usage.md`
- `check_remaining_empty_codes.sh` — 一键生成剩余可缩码报告(shrink_empty_codes_report_remaining.txt),并提示 apply 命令
- `reorder_same_code_by_length.py` — 各词库文件内部,同码条目按词长重排(短词在前),报告 same_code_length_order_report.txt
- `move_cross_file_same_code_short_first.py` — 跨文件的同码组抽入 `xmjd6.same_code_short_first.dict.yaml` 并短词优先,该库在 extended 中紧跟 wxw 之后导入
- `wxw_analyze.py` — 分析 wxw 630 简词库(见下节)

### 词库生成 / 转换

- `py2jd.py` — 拼音词组批量转键道音形码:
  1. 个人词库(*.dict.yaml)放当前目录
  2. 待补码词组复制进 `All.txt`,每行一词,无多余编码
  3. 执行 `python3 py2jd.py`
  4. 生成 `xkjd6.result.dict.yaml`(依赖 `jdx.csv` 单字形码表)
- `he1.py` — 按 extended 的 import 顺序合并全部词库 → `v6.txt`(每行:码\t候选1\t候选2…)
- `scripts/toTxt.py` — 全部词库导出:>4 码 → `duanyu.txt`("1,code=词"格式),≤4 码 → `wenzi.txt`
- `fanzhuan.py` — `v6.txt` 词/码两列对调 → `v62.txt`
- `zhuyin.py` — 给词库加拼音注音(pypinyin,运行后输入文件路径,输出 `new.yaml`)

### 词库清理(多为一次性)

- `clean_dict.py` — 清理 fjcy / lanlao / lanlao2 中的人名、地名、诗句、音译等废词
- `shanfeici.py` — 下载 jieba 词典做对照,判定并清理废词
- `shanci.py` — lanlao2 删除超过 4 字的词
- `quyou.py` — fjcy 提取纯词列(去编码)
- `qui.py` — 唐诗库编码去掉 i 前缀
- `chongfu.py` — 已废弃(曾用于查跨库重复编码)

## wxw 630 简词库维护

630 编码规则:简码 = 首字声母键 + 次字首二笔形码(2 码取首笔,3 码取首二笔;a=折 i=竖 o=点 u=撇 v=横)

- `wxw_analyze.py` — 分析 `xmjd6.wxw.dict.yaml`:全表验证编码规则、把想加的词(脚本内 WISH 列表)定位到自洽码位并显示当前占用者、反查每个码位上更高频的可换词
  - 运行:`python3 wxw_analyze.py`,报告输出到 `/tmp/wxw_report.txt`
  - 形码来自 `xmjd6.danzi`(单字全码第 3-4 码),声母键来自 `xmjd6.cizu`(词条首码),词频参考 `pinyin_simp`(语料较老,网络新词需人工判断)
- 换词方式:直接编辑 `xmjd6.wxw.dict.yaml`,新词一行 + `# 原词` 注释保留可回滚;同码多词时靠前为首选(`sort: original`)
- 改完重新部署 Rime 生效
