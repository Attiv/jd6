# script.py
# 读取v6.txt文件的内容
with open('v6.txt', 'r') as file:
    lines = file.readlines()
# 使用split()函数和制表符（\t）将每一行的编码和文字反过来，编码在前，文字在后
lines = ['\t'.join(reversed(line.strip().split('\t'))) for line in lines]
# 将处理后的内容写回v6.txt文件
with open('v62.txt', 'w') as file:
    file.write('\n'.join(lines))