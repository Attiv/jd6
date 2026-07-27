#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""wxw 630 简词库分析:验证编码规则 + 反查可替换的高频词。

630 编码规则: 简码 = 首字声母键 + 次字首二笔形码(2 码取首笔, 3 码取首二笔)
形码键位: a=折 i=竖 o=点 u=撇 v=横(部分部首为整根, 如 氵=a 扌=iu 亻=ui)

数据来源:
- xmjd6.danzi.dict.yaml  单字全码(第 3-4 码即形码前二笔) -> 每字的形码
- xmjd6.cizu.dict.yaml   二字词全码首码 -> 每字作首字时的声母键(涵盖 zh/ch/sh 分键)
- pinyin_simp.dict.yaml  词频参考(语料较老, 网络新词频率偏低, 需人工判断)
- xmjd6.wxw.dict.yaml    被分析的 630 简词库
- xmjd6.buchong.dict.yaml 已有自建简码的词(避免重复建议)

用法: python3 wxw_analyze.py
输出: /tmp/wxw_report.txt, 共三段:
  1) 规则验证      -- 630 全表回归, 列出不符条目(一般为多音字)
  2) 心愿词定位    -- WISH 列表中每个词的自洽 2/3 码及当前占用者
  3) 全槽位反查    -- 每个码位上编码自洽的最高频候选, 按替换价值排序
"""
import re
from collections import Counter, defaultdict

RIME = "/Users/mac/Library/Rime"
HAN = lambda w: all('一' <= c <= '鿿' for c in w)


def parse_tab_dict(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#")[0]
            parts = line.rstrip().split("\t")
            if len(parts) >= 2 and parts[0] and HAN(parts[0]) \
               and re.fullmatch(r"[a-z]+", parts[1].strip() or ""):
                rows.append((parts[0], parts[1].strip()))
    return rows


# ---------- 声母键: 从 cizu 学 ----------
skey_c = defaultdict(Counter)
for w, code in parse_tab_dict(f"{RIME}/xmjd6.cizu.dict.yaml"):
    if len(w) == 2 and len(code) >= 4:
        skey_c[w[0]][code[0]] += 1
mode = lambda cnt: cnt.most_common(1)[0][0] if cnt else None
skey = {c: mode(v) for c, v in skey_c.items()}

# ---------- 形码: 从 danzi 学 ----------
sh1_c, sh2_c = defaultdict(Counter), defaultdict(Counter)
for w, code in parse_tab_dict(f"{RIME}/xmjd6.danzi.dict.yaml"):
    if len(w) != 1:
        continue
    if len(code) >= 3:
        sh1_c[w][code[2]] += 1
    if len(code) >= 4:
        sh2_c[w][code[2:4]] += 1
sh1 = {c: mode(v) for c, v in sh1_c.items()}
sh2 = {c: mode(v) for c, v in sh2_c.items()}

# ---------- wxw / buchong / 词频 ----------
wxw = parse_tab_dict(f"{RIME}/xmjd6.wxw.dict.yaml")
wxw_words = {w for w, _ in wxw}
wxw_by_code = defaultdict(list)
for w, c in wxw:
    wxw_by_code[c].append(w)

buchong_words = {w for w, c in parse_tab_dict(f"{RIME}/xmjd6.buchong.dict.yaml")
                 if len(w) == 2 and len(c) <= 3}

freq = {}
with open(f"{RIME}/pinyin_simp.dict.yaml", encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) == 3 and len(parts[0]) == 2 and HAN(parts[0]):
            try:
                fr = int(float(parts[2]))
            except ValueError:
                continue
            if fr > freq.get(parts[0], -1):
                freq[parts[0]] = fr

out = open("/tmp/wxw_report.txt", "w", encoding="utf-8")

# ---------- 1) 规则验证 ----------
ok, bad, unk, bad_rows = 0, 0, 0, []
for w, code in wxw:
    if len(w) != 2 or not (2 <= len(code) <= 3):
        continue
    k = skey.get(w[0])
    s = sh1.get(w[1]) if len(code) == 2 else sh2.get(w[1])
    if not k or not s:
        unk += 1
        continue
    if k + s == code:
        ok += 1
    else:
        bad += 1
        bad_rows.append(f"{w} {code} (规则码 {k}{s})")

out.write("== 规则验证: 码 = 首字声母键 + 次字首二笔形码 ==\n")
out.write(f"自洽 {ok} / 不符 {bad} / 缺映射 {unk}\n不符条目:\n")
out.write("\n".join(bad_rows) + "\n\n")

# ---------- 2) 心愿词定位: 想加的词填在这里 ----------
WISH = ("哈哈 晚安 老婆 老公 妹妹 三观 输入 这些 吐槽 衣服 旅游 餐厅 菜单 厕所 "
        "辞职 咖啡 姐姐 不要 比较 一些 我也 孩子 电话 儿子 辛苦 名字 学校 为啥 "
        "客户 下班 回复 讨论 摸鱼 宝宝 设计 睡觉 最近 原来 确定 反正 加班 放假 "
        "请假 生气 开会 红包 快递 爸爸 哥哥 奶奶 周末 超市 外面").split()

out.write("== 心愿词 -> 自洽码(2码/3码)及当前占用者 ==\n")
for w in dict.fromkeys(WISH):
    if len(w) != 2:
        continue
    tag = " [已在630]" if w in wxw_words else (" [已有自建简码]" if w in buchong_words else "")
    k, s1v, s2v = skey.get(w[0]), sh1.get(w[1]), sh2.get(w[1])
    c2 = k + s1v if k and s1v else "??"
    c3 = k + s2v if k and s2v else "??"
    o2 = "/".join(wxw_by_code.get(c2, ["<空>"]))
    o3 = "/".join(wxw_by_code.get(c3, ["<空>"]))
    out.write(f"{w}(频{freq.get(w,0)}){tag}: 2码 {c2}={o2}(频{freq.get(o2,0)}) | "
              f"3码 {c3}={o3}(频{freq.get(o3,0)})\n")
out.write("\n")

# ---------- 3) 全槽位反查 ----------
cands = defaultdict(list)
for w, fr in freq.items():
    if w in wxw_words or w in buchong_words or fr < 200:
        continue
    k = skey.get(w[0])
    if not k:
        continue
    s1v, s2v = sh1.get(w[1]), sh2.get(w[1])
    if s1v:
        cands[k + s1v].append((fr, w))
    if s2v:
        cands[k + s2v].append((fr, w))
for c in cands:
    cands[c].sort(reverse=True)

rows = []
for w, code in wxw:
    old_f = freq.get(w, 0)
    top = cands.get(code, [])[:5]
    ratio = (top[0][0] / (old_f + 1)) if top else 0
    rows.append((ratio, code, w, old_f, top))
rows.sort(key=lambda r: -r[0])

out.write("== 全部槽位按(最高候选频/原词频)排序, 前 200 行 ==\n")
for ratio, code, w, old_f, top in rows[:200]:
    tops = " ".join(f"{t[1]}({t[0]})" for t in top)
    out.write(f"{code}\t{w}(频{old_f})\t=> {tops}\n")
out.close()
print("done -> /tmp/wxw_report.txt")
