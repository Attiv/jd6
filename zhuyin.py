# 给字加拼音声调，有点小问题，文件的头几行介绍也会给加上，手动删了就行，不想改了

import sys
import os
import pypinyin


def main():
    # 获取用户输入的文件路径
    yaml_path = input("请输入指令文件路径：")

    # 获取脚本所在目录
    script_dir = os.path.dirname(os.path.realpath(__file__))

    # 构造新文件路径
    output_path = os.path.join(script_dir, "new.yaml")

    # 打开输入文件
    with open(yaml_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # 遍历每一行
    new_lines = []
    for line in lines:
        # 去除空行和注释
        line = line.strip()
        if line.startswith("#") or line == "":
            new_lines.append(line)
            continue

        # 获取汉字
        hanzi = line.split("/t")[0]

        # 获取注音
        pinyin_result = pypinyin.lazy_pinyin(hanzi, style="tone3")[0]

        # 将音调符号转换为拼音格式
        pinyin_result = pinyin_result.replace("_", "")

        # 追加注音到行尾
        line += f"\t〔{pinyin_result}〕"

        # 添加到新行列表
        new_lines.append(line)

    # 写入新文件
    with open(output_path, "w", encoding="utf-8") as output_file:
        output_file.writelines('\n'.join(new_lines))

    print(f"已将注音后的内容保存到 {output_path} 文件中。")


if __name__ == "__main__":
    main()
