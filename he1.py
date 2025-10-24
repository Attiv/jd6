# script.py
import glob
import os

# 获取当前目录下所有.dict.yaml文件的列表
files = glob.glob('./*.dict.yaml')
entries = {}

# 遍历所有.dict.yaml文件
for filename in files:
    basename = os.path.basename(filename)
    # 忽略pinyin_simp.dict.yaml文件和以english开头的文件
    if basename == 'pinyin_simp.dict.yaml' or basename.startswith('english'):
        continue
    # 读取当前文件的内容
    with open(filename, 'r', encoding='utf-8') as infile:
        # 逐行检查
        for raw_line in infile:
            # 如果该行不符合给定的规则，则跳过
            if raw_line.startswith(('#', '---', '...', 'name:', 'version:', 'sort:')):
                continue
            line = raw_line.strip()
            # 如果该行不包含制表符或为空，则跳过
            if not line or '\t' not in line:
                continue
            # 将行拆分为部分
            parts = [part.strip() for part in line.split('\t') if part.strip()]
            # 如果部分少于2个，则跳过
            if len(parts) < 2:
                continue
            # 获取代码和候选项
            candidate = parts[0]
            code = parts[1]
            # 获取或创建代码的条目
            target = entries.setdefault(code, [])
            # 将候选项添加到条目中
            if candidate not in target:
                target.append(candidate)

# 在新的txt文件中打开写入模式
with open('v6.txt', 'w', encoding='utf-8', newline='\n') as outfile:
    # 遍历条目并写入文件
    for code, candidates in entries.items():
        outfile.write('\t'.join([code] + candidates) + '\n')