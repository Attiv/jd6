import os
import glob

# 获取当前目录下所有的*.dict.yaml文件
yaml_files = glob.glob('./*.dict.yaml')

# 排除的文件列表
exclude_files = ['xmjd6.gbk.dict.yaml', 'xmjd6cx.dict.yaml',
                 'xkjd6dz.dict.yaml', 'pinyin_simp.dict.yaml', 'xmjd6.en.dict.yaml']

# 从所有的*.dict.yaml文件中移除排除的文件
yaml_files = [file for file in yaml_files if os.path.basename(
    file) not in exclude_files]

# 打开两个新的txt文件，用于写入结果
with open('duanyu.txt', 'w', encoding='utf-8') as duanyu_file, open('wenzi.txt', 'w', encoding='utf-8') as wenzi_file:
    # 遍历每一个yaml文件
    for yaml_file in yaml_files:
        # 打开当前的yaml文件
        with open(yaml_file, 'r', encoding='utf-8') as file:
            # 遍历文件的每一行
            for line in file:
                # 如果该行包含制表符
                if '\t' in line:
                    # 则取出制表符后的文字
                    # text = line.split('\t')[1]
                    character, code = line.split("\t")
                    # 根据字母编码长度将内容写入到不同的txt文件中
                    if len(code.strip()) > 4:
                        duanyu_file.write(f"1,{code}={character}\n")
                    else:
                        wenzi_file.write(line)
