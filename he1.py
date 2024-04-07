# script.py
import glob
# 获取当前目录下所有.dict.yaml文件的列表
files = glob.glob('./*.dict.yaml')
# 在新的YAML文件中打开写入模式
with open('v6.yaml', 'w') as outfile:
    # 遍历所有.dict.yaml文件
    for filename in files:
        # 忽略pinyin_simp.dict.yaml文件
        if 'pinyin_simp.dict.yaml' in filename:
            continue
        # 读取当前文件的内容
        with open(filename, 'r') as infile:
            # 逐行检查
            for line in infile:
                # 如果该行不符合给定的规则，则将其写入新的YAML文件中
                if not (line.startswith('#') or line.startswith('---') or line.startswith('name:') or line.startswith('version:') or line.startswith('sort:') or line.startswith('...')):
                    outfile.write(line)