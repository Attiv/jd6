#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Rime 词库废词清理脚本
清理对象：xmjd6.fjcy.dict.yaml / xkjd6.lanlao2.dict.yaml / xkjd6.lanlao.dict.yaml
废词类型：地名、人名、诗句/古文、外国地名音译
"""

import re
import os

# ── 常见姓氏 ──────────────────────────────────────────────────────────────────
SURNAMES = set('李王张刘陈杨黄赵吴周徐孙马朱胡郭何高林罗郑梁谢宋唐许韩冯邓曹彭曾肖田董袁潘于蒋蔡余杜叶程苏魏吕丁任沈姚卢姜崔钟谭陆汪范金石廖贾夏韦付方白邹孟熊秦邱江尹薛闫段雷侯龙史陶黎贺顾毛郝龚邵万钱严覃武戴莫孔向汤聂')
COMPOUND_SURNAMES = {'司马'}

# ── 常见人名用字（名字部分，后1-2字）────────────────────────────────────────
# 这些字单独或组合出现在姓氏后，高概率是人名
NAME_CHARS = set('伟芳娜秀英华慧巧美娟秋霞平云莲真环雪荣爱妹霞香月莺媛艳瑞凤琴麻'
                 '明亮国华建军平保红文强磊军勇涛超俊峰辉鹏飞宇浩博文杰志远鑫'
                 '晓雨欣雪婷玲燕丽娜静敏倩璐璇瑶琪琳晶晨曦颖'
                 '志明建国庆华伟东海洋天宇宏亮鹏飞俊杰浩然'
                 '宝琛洁仪海胜树斌振邦相如承祯睿德文朗丕绍衍彪望徽楚艾宏婕远')
NAME_PREFIX_CHARS = {'小', '子', '阿'}

# 人名常见后缀2字组合（高置信度）
NAME_BIGRAMS = {
    '小红', '小明', '小华', '小燕', '小玲', '小丽', '小芳', '小梅', '小兰',
    '建国', '建军', '建华', '建平', '建明', '建文', '建斌', '建峰',
    '志远', '志强', '志明', '志刚', '志伟', '志鹏', '志豪',
    '晓龙', '晓明', '晓燕', '晓红', '晓华', '晓峰', '晓波',
    '玉荣', '玉梅', '玉兰', '玉珍', '玉华', '玉英',
    '海龙', '海燕', '海涛', '海波', '海峰', '海军',
    '新民', '新华', '新建', '新国', '新军',
    '剑峰', '剑波', '剑锋',
    '鹏飞', '鹏程',
    '曙光', '启明',
    '汶锜', '贻可', '又安', '启瑞',
}

# 高置信度非人名词（含姓氏但不是人名）
NOT_NAME_PATTERNS = [
    re.compile(p) for p in [
        r'.+矿$', r'.+鹿$', r'.+油$', r'.+花$', r'.+草$', r'.+树$', r'.+鸟$',
        r'.+虫$', r'.+鱼$', r'.+蛇$', r'.+猫$', r'.+狗$', r'.+马$', r'.+牛$',
        r'.+石$', r'.+山$', r'.+水$', r'.+河$', r'.+湖$', r'.+海$',
        r'.+路$', r'.+街$', r'.+村$', r'.+镇$', r'.+县$',
        r'.+度$', r'.+率$', r'.+量$', r'.+性$', r'.+力$', r'.+感$',
        r'.+上$', r'.+下$', r'.+中$', r'.+内$', r'.+外$',
        r'.+的$', r'.+了$', r'.+着$', r'.+过$',
        r'.+学$', r'.+术$', r'.+法$', r'.+式$', r'.+型$',
        r'.+局$', r'.+部$', r'.+厅$', r'.+院$', r'.+所$',
        r'.*[0-9].*',  # 含数字
    ]
]

# ── 地名后缀 ──────────────────────────────────────────────────────────────────
# 强地名后缀：结尾是这些字，高概率是地名
GEO_STRONG_SUFFIX = set('乡镇寨苑巷坊屯堡郡坪县洲岛港村')

# 弱地名后缀：需要额外判断
GEO_WEAK_SUFFIX = set('路街湾山湖河庄铺沟坡府城园')
GEO_THREE_CHAR_SUFFIX = {'庭', '院', '轩', '居'}
GEO_MULTI_SUFFIX = ('胡同',)

ANATOMY_HINT_CHARS = set('鼻唇喉肛膜鞘泪腭颈胸腹肋眼耳口舌气筋脉骨前后内外上下左右横纵面间阴')

# 明显不是地名的词（含弱后缀但是普通词）
NOT_GEO_PATTERNS = [
    re.compile(p) for p in [
        # 含"路"但不是地名
        r'.*电路.*', r'.*线路.*', r'.*道路.*', r'.*铁路.*', r'.*公路.*',
        r'.*网络.*', r'.*思路.*', r'.*出路.*', r'.*走路.*', r'.*迷路.*',
        r'.*修路.*', r'.*铺路.*', r'.*路线.*', r'.*路程.*', r'.*路途.*',
        r'.*之路$', r'.*的路$', r'.*小路$', r'.*路上$', r'.*跑路.*',
        r'.*分路.*', r'.*进路.*', r'.*出路.*', r'.*退路.*', r'.*思路.*',
        r'.*漫步.*', r'.*门路.*', r'.*销路.*', r'.*财路.*', r'.*生路.*',
        r'.*死路.*', r'.*末路.*', r'.*上路.*', r'.*下路.*', r'.*回路.*',
        # 含"山"但不是地名
        r'.*青山.*', r'.*高山.*', r'.*大山.*', r'.*山水.*', r'.*山川.*',
        r'.*山河.*', r'.*山峰.*', r'.*山谷.*', r'.*山林.*', r'.*山地.*',
        r'.*泰山.*', r'.*崇山.*', r'.*残山.*', r'.*画山.*',
        # 含"湖"但不是地名
        r'.*湖水.*', r'.*湖面.*', r'.*湖边.*', r'.*湖泊.*',
        # 含"河"但不是地名
        r'.*河流.*', r'.*河水.*', r'.*河边.*', r'.*银河.*',
        # 含"街"但不是地名
        r'.*街道.*', r'.*街头.*', r'.*街市.*', r'.*上街.*', r'.*下街.*',
        # 含"湾"但不是地名
        r'.*台湾.*',
        # 含"庄"但不是地名
        r'.*庄严.*', r'.*庄重.*', r'.*庄稼.*',
        # 含"铺"但不是地名
        r'.*当铺$', r'.*店铺$', r'.*饭铺$', r'.*粥铺$', r'.*药铺$', r'.*查铺$',
        r'.*货铺$', r'.*茶铺$', r'.*香蜡铺$', r'.*小卖铺$', r'.*通铺$', r'.*床铺$',
        r'.*[上下内外前后]铺$', r'.*铺路.*',
        # 含"沟"但不是地名
        r'.*鸿沟$', r'.*纹沟$', r'.*檐沟$', r'.*泪沟$', r'.*代沟$', r'.*状沟$',
        r'.*发育沟$', r'.*车道沟$',
        # 含"坡"但不是地名
        r'.*斜坡$', r'.*山坡$', r'.*上坡$', r'.*下坡$', r'.*风坡$', r'.*土坡$',
        r'.*高坡$', r'.*平改坡$', r'.*大陆坡$', r'.*新加坡$', r'.*科伦坡$',
        r'.*可伦坡$', r'.*爱伦坡$',
        # 含"府"但不是地名
        r'.*政府$', r'.*官府$', r'.*学府$', r'.*城府$', r'.*乐府$', r'.*韵府$',
        r'.*秘府$', r'.*王府$', r'.*首相府$', r'.*将军府$',
        # 含"城"但不是地名
        r'.*围城$', r'.*书城$', r'.*商城$', r'.*中国城$', r'.*太阳城$', r'.*赌城$',
        r'.*这座城$', r'.*废城$',
        # 含"园"但不是地名
        r'.*公园$', r'.*花园$', r'.*家园$', r'.*校园$', r'.*乐园$', r'.*庄园$',
        r'.*果园$', r'.*菜园$', r'.*草莓园$', r'.*葡萄园$', r'.*农业园$',
        r'.*示范园$', r'.*恐龙园$',
        # 含"县/区"但不是地名
        r'.*小区.*', r'.*城区.*', r'.*地区.*', r'.*州区.*', r'.*县区.*',
        r'.*区县.*', r'.*所在.*', r'.*欧洲.*', r'.*亚洲.*', r'.*关注.*',
        r'.*统治.*', r'.*多个.*', r'.*号路.*', r'.*三街.*',
    ]
]

# ── 诗句/古文特征 ─────────────────────────────────────────────────────────────
WENYAN_CHARS = set('兮乎哉矣焉耳')
# 古诗常见词（出现则高概率是诗句）
POETRY_WORDS = ['离离', '原上', '春风', '秋月', '明月', '白云', '青山', '绿水',
                '千里', '万里', '江南', '塞北', '烽火', '战鼓', '旌旗']

# ── 外国地名音译特征 ──────────────────────────────────────────────────────────
# 含这些字且整词像音译（无汉语语义）
FOREIGN_CHARS = set('巴斯特拉克维亚尼亚斯坦堡')


def is_geo_name(word):
    """判断是否是地名"""
    if len(word) < 2 or len(word) > 8:
        return False

    # 检查是否匹配非地名模式
    for pat in NOT_GEO_PATTERNS:
        if pat.match(word):
            return False

    if any(word.endswith(suffix) for suffix in GEO_MULTI_SUFFIX):
        return 3 <= len(word) <= 8

    # 强地名后缀
    if word[-1] in GEO_STRONG_SUFFIX and len(word) >= 2:
        # 排除一些常见非地名
        if word in {'欧罗巴洲', '亚细亚洲'}:
            return True
        # 2-6字的强后缀词，高概率地名
        if 2 <= len(word) <= 6:
            return True

    if len(word) == 3 and word[-1] in GEO_THREE_CHAR_SUFFIX:
        if word[-1] in {'庭', '轩', '居'} and word[0] in SURNAMES:
            return False
        if word.endswith(('家庭', '法庭', '前庭', '开庭', '公庭', '天庭')):
            return False
        if word.endswith(('医院', '学院', '法院', '书院', '病院', '剧院', '戏院',
                          '议院', '大院', '画院')):
            return False
        if word.endswith(('邻居', '家居', '同居', '新居', '起居', '隐居', '宜居')):
            return False
        return True

    if word[-1] == '城' and len(word) >= 2:
        return True

    # 弱地名后缀：需要更严格判断
    if word[-1] in GEO_WEAK_SUFFIX and len(word) >= 3:
        # 含数字或方位词开头，高概率地名
        if re.match(r'^[东南西北上下左右前后][^\s]', word):
            return True
        # X+X+路/街 格式（如"漕宝路"、"福华路"）
        if len(word) == 3 and word[-1] in {'路', '街'}:
            # 排除常见非地名
            common_non_geo = {'小路', '大路', '出路', '走路', '迷路', '铺路', '修路',
                              '上街', '下街', '赶街', '跑路', '带路', '让路', '让街'}
            if word not in common_non_geo:
                return True
        # 4字以上的弱后缀，且不含常见动词/形容词
        if len(word) >= 4 and word[-1] in {'路', '街'}:
            # 排除含动词的词组（如"崩盘跑路"）
            verb_chars = '跑跳走踢打推拉搬爬骑坐躺站闯逃追'
            if any(c in word[:-1] for c in verb_chars):
                return False
            # 如果前面部分像地名（含专有名词特征）
            prefix = word[:-1]
            if not any(c in prefix for c in '的了着过很非常'):
                return True

        if word[-1] == '沟':
            if any(c in word[:-1] for c in ANATOMY_HINT_CHARS):
                return False
            return True

        if word[-1] in {'庄', '铺', '坡', '府', '园'}:
            return True

        if word[-1] == '湾':
            return '台湾' not in word

        if word[-1] == '城':
            return len(word) >= 2

    return False


def is_person_name(word):
    """判断是否是人名（真实人名）"""
    if len(word) < 2 or len(word) > 4:
        return False
    if not re.match(r'^[\u4e00-\u9fff]+$', word):
        return False

    # 检查非人名模式
    for pat in NOT_NAME_PATTERNS:
        if pat.match(word):
            return False

    if word in {'陈述', '陈述句', '聂拉木', '司马法', '司马氏'}:
        return False
    if word.endswith(('老师', '女士', '先生')):
        return False

    def looks_like_given_name(name):
        if len(name) == 1:
            return name in NAME_CHARS
        if len(name) == 2:
            if name in NAME_BIGRAMS:
                return True
            if name[0] in NAME_PREFIX_CHARS and name[1] in NAME_CHARS:
                return True
            if name[0] in NAME_CHARS and name[1] in NAME_CHARS:
                return True
        return False

    for surname in COMPOUND_SURNAMES:
        if word.startswith(surname):
            return looks_like_given_name(word[len(surname):])

    if word[0] not in SURNAMES:
        return False

    return looks_like_given_name(word[1:])


def is_poetry(word):
    """判断是否是诗句/古文"""
    if len(word) < 4 or len(word) > 20:
        return False

    # 排除含数字或常见现代词的
    if re.search(r'[0-9]', word):
        return False

    # 五言或七言格式（纯汉字，无标点）
    if len(word) in {5, 7} and re.match(r'^[\u4e00-\u9fff]+$', word):
        # 含古诗常见词
        if any(pw in word for pw in POETRY_WORDS):
            return True
        # 五言/七言且有文言虚词
        if any(c in word for c in WENYAN_CHARS):
            return True

    # 更严格：必须同时满足多个条件才算诗句
    wenyan_count = sum(1 for c in word if c in WENYAN_CHARS)
    poetry_word_count = sum(1 for pw in POETRY_WORDS if pw in word)

    # 同时满足：多个文言虚词 或 多个古诗常见词
    if wenyan_count >= 2 or poetry_word_count >= 2:
        # 再排除一些常见搭配
        if not any(p in word for p in ['听觉', '听力', '耳机', '耳鸣', '耳语', '耳旁']):
            return True

    return False


def is_foreign_place(word):
    """判断是否是外国地名音译"""
    if len(word) < 3 or len(word) > 6:
        return False
    # 全部是汉字
    if not re.match(r'^[\u4e00-\u9fff]+$', word):
        return False
    # 含大量音译特征字
    foreign_count = sum(1 for c in word if c in FOREIGN_CHARS)
    if foreign_count >= 2 and len(word) <= 4:
        return True
    return False


def should_delete(word):
    """综合判断是否应该删除"""
    if not word or len(word) == 0:
        return False, None

    if is_person_name(word):
        return True, '人名'
    if is_geo_name(word):
        return True, '地名'
    if is_poetry(word):
        return True, '诗句'
    # if is_foreign_place(word):
    #     return True, '外国地名'

    return False, None


def process_file(input_path, deleted_path, dry_run=False):
    """处理单个词库文件"""
    print(f"\n{'='*60}")
    print(f"处理: {os.path.basename(input_path)}")
    print(f"{'='*60}")

    with open(input_path, 'r', encoding='utf-8-sig') as f:
        content = f.read()

    # 检测是否有 BOM
    has_bom = content.startswith('\ufeff') if False else False
    with open(input_path, 'rb') as f:
        raw = f.read(3)
        has_bom = raw[:3] == b'\xef\xbb\xbf'

    lines = content.split('\n')

    # 找到 yaml 头结束位置（...）
    header_end = 0
    for i, line in enumerate(lines):
        if line.strip() == '...':
            header_end = i
            break

    header_lines = lines[:header_end + 1]
    data_lines = lines[header_end + 1:]

    kept = []
    deleted = []
    stats = {'地名': 0, '人名': 0, '诗句': 0, '外国地名': 0}

    for line in data_lines:
        stripped = line.strip()

        # 空行和注释保留
        if not stripped or stripped.startswith('#'):
            kept.append(line)
            continue

        # 提取词条（Tab分隔，第一列是词）
        parts = line.split('\t')
        word = parts[0].strip()

        if not word:
            kept.append(line)
            continue

        delete, reason = should_delete(word)

        if delete:
            deleted.append(line)
            stats[reason] = stats.get(reason, 0) + 1
        else:
            kept.append(line)

    total_data = sum(1 for l in data_lines if l.strip() and not l.strip().startswith('#'))
    print(f"总词条数: {total_data:,}")
    print(f"删除词条: {len(deleted):,} ({len(deleted)/max(total_data,1)*100:.1f}%)")
    print(f"  - 地名: {stats.get('地名', 0):,}")
    print(f"  - 人名: {stats.get('人名', 0):,}")
    print(f"  - 诗句: {stats.get('诗句', 0):,}")
    print(f"保留词条: {total_data - len(deleted):,}")

    if not dry_run:
        # 写回原文件
        new_content = '\n'.join(header_lines + kept)
        # 保持原始编码（有BOM则加BOM）
        write_mode = 'utf-8-sig' if has_bom else 'utf-8'
        with open(input_path, 'w', encoding=write_mode, newline='') as f:
            f.write(new_content)
        print(f"✅ 已写回: {input_path}")

        # 写删除记录
        with open(deleted_path, 'w', encoding='utf-8') as f:
            f.write(f"# 从 {os.path.basename(input_path)} 删除的词条\n")
            f.write(f"# 共 {len(deleted)} 条，如需恢复请手动添加回词库\n")
            f.write(f"# 格式：词条<Tab>编码\n\n")
            for line in deleted:
                f.write(line + '\n')
        print(f"✅ 删除记录: {deleted_path}")
    else:
        print("\n[DRY RUN] 前20条将被删除的词:")
        for line in deleted[:20]:
            print(f"  {line}")

    return len(deleted), total_data


# ── 正式执行 ───────────────────────────────────────────────────────────────────
print("=" * 60)
print("正式执行 - 清理废词")
print("=" * 60)

files = [
    ('/Users/mac/Library/Rime/xmjd6.fjcy.dict.yaml',
     '/Users/mac/Library/Rime/deleted_fjcy.txt'),
    ('/Users/mac/Library/Rime/xkjd6.lanlao2.dict.yaml',
     '/Users/mac/Library/Rime/deleted_lanlao2.txt'),
    ('/Users/mac/Library/Rime/xkjd6.lanlao.dict.yaml',
     '/Users/mac/Library/Rime/deleted_lanlao.txt'),
]

total_deleted = 0
total_count = 0

for input_path, deleted_path in files:
    deleted, total = process_file(input_path, deleted_path, dry_run=False)
    total_deleted += deleted
    total_count += total

print("\n" + "=" * 60)
print(f"🎉 清理完成！")
print(f"总词条数: {total_count:,}")
print(f"总删除数: {total_deleted:,} ({total_deleted/max(total_count,1)*100:.1f}%)")
print(f"总保留数: {total_count - total_deleted:,}")
print("=" * 60)
print("\n删除记录文件位置：")
print("  - /Users/mac/Library/Rime/deleted_fjcy.txt")
print("  - /Users/mac/Library/Rime/deleted_lanlao2.txt")
print("  - /Users/mac/Library/Rime/deleted_lanlao.txt")
