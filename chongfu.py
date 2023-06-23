# import glob
# import os

# # 排除的文件列表
# exclude_files = [
#     "xkjd6.gbk.dict.yaml",
#     "xkjd6cx.dict.yaml",
#     "xkjd6dz.dict.yaml",
#     "pinyin_simp.dict.yaml",
#     "xmjd6.en.dict.yaml",
#     "xkjd6.yixue.dict.yaml",
#     "liangfen.dict.yaml",
# ]

# # 获取当前目录下的所有 *.dict.yaml 文件，排除 exclude_files 中的文件
# file_list = [
#     file for file in glob.glob("*.dict.yaml") if file not in exclude_files
# ]

# code_dict = {}

# # 处理每个文件
# for file_name in file_list:
#     with open(file_name, "r", encoding="utf-8") as file:
#         for line in file.readlines():
#             if line.startswith("#"):  # 跳过注释行
#                 continue
#             parts = line.split("\t")
#             if len(parts) > 1:
#                 code = parts[1].strip()
#                 if code in code_dict:
#                     code_dict[code].append(file_name)
#                 else:
#                     code_dict[code] = [file_name]

# # 查找重复的编码并保存到 chongfu.txt
# with open("chongfu.txt", "w", encoding="utf-8") as chongfu_file:
#     for code, files in code_dict.items():
#         if len(files) > 1:
#             chongfu_file.write(
#                 f"编码: {code} 重复于以下文件: {', '.join(files)}\n"
#             )

import os

def check_duplicate_codes():
    files = []
    duplicate_codes = {}

    # 获取当前目录下的所有 *.dict.yaml 文件
    for file in os.listdir('.'):
        if file.endswith('.dict.yaml') and file not in ['xkjd6.gbk.dict.yaml', 'xkjd6cx.dict.yaml', 'xkjd6dz.dict.yaml', 'pinyin_simp.dict.yaml', 'xmjd6.en.dict.yaml', 'liangfen.dict.yaml', 'xkjd6.yixue.dict.yaml']:
            files.append(file)

    # 检查编码是否完全重复
    for file in files:
        with open(file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            for line in lines:
                parts = line.strip().split('\t')
                if len(parts) == 2:
                    code = parts[1]
                    if code in duplicate_codes:
                        duplicate_codes[code].append((line.strip(), file))
                    else:
                        duplicate_codes[code] = [(line.strip(), file)]

    # 将结果输出到 chongfu.txt 文件
    with open('chongfu.txt', 'w', encoding='utf-8') as f:
        for code, occurrences in duplicate_codes.items():
            if len(occurrences) > 1:
                f.write(f'Repeated Code: {code}\n')
                for occurrence in occurrences:
                    f.write(f'File: {occurrence[1]}, Line: {occurrence[0]}\n')
                f.write('\n')

# 执行检查
check_duplicate_codes()
