1、将个人词库文件放置在当前目录下，词库格式为 *.dict.yaml
2、将需要空码补充的词库内容复制进 All.txt，每行一词，无多余编码
3、完成以上两步后，在当前目录执行 python3 py2jd.py
4、等待一会儿，词库生成为 xkjd6.result.dict.yaml

---

## wxw 630 简词库维护

630 编码规则：简码 = 首字声母键 + 次字首二笔形码（2 码取首笔，3 码取首二笔；a=折 i=竖 o=点 u=撇 v=横）

- `wxw_analyze.py` — 分析 `xmjd6.wxw.dict.yaml`：全表验证编码规则、把想加的词（脚本内 WISH 列表）定位到自洽码位并显示当前占用者、反查每个码位上更高频的可换词
  - 运行：`python3 wxw_analyze.py`，报告输出到 `/tmp/wxw_report.txt`
  - 形码来自 `xmjd6.danzi`（单字全码第 3-4 码），声母键来自 `xmjd6.cizu`（词条首码），词频参考 `pinyin_simp`（语料较老，网络新词需人工判断）
- 换词方式：直接编辑 `xmjd6.wxw.dict.yaml`，新词一行 + `# 原词` 注释保留可回滚；同码多词时靠前为首选（`sort: original`）
- 改完重新部署 Rime 生效