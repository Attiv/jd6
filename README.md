# 星猫键道6 Rime 配置

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
