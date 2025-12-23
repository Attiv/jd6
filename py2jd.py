# All.txt，存放需要转换的词组，每行一词，无多余编码
# jdx.csv，单字的首笔形码，用的 RIME_JD 的单字码表
# jdAllx.csv，最后得到的键道音形码文件

# 导入需要的模块
import glob
import re, csv, pandas, os
from pypinyin import pinyin, lazy_pinyin, Style

print('正在处理，请稍等……（参考： 平均1万词大约10秒时间，转化完成后，窗口会自动关闭）')

# 判断文件是否存在
file_list = ['jdAll.csv', 'jdAllx.csv', 'jdf.csv', 'jdy.csv', 'jdyf.csv', 'pinyin.csv', '已有字词.txt', '已有编码.txt', 'result.dict.yaml']
for file in file_list:
    if os.path.exists(file):
        os.remove(file)

# 把词组存储到 Alltxt 列表中
with open('./All.txt', 'r', encoding='UTF-8-SIG') as f:
    Alltxt = f.readlines()

# 使用 pyinyin 为词组注音，并写入 pinyin.csv
with open('pinyin.csv', 'w', encoding='UTF-8') as Allpinyin:
    for ci in Alltxt:
        Allpinyin.write(ci.rstrip()+'\t')
        sh = lazy_pinyin(ci, style=Style.INITIALS, strict=False, errors='ignore') # 取声母为列表
        un = lazy_pinyin(ci, style=Style.FINALS, strict=False, errors='ignore') #取韵母为列表
        n = 0
        while n < len(un):
            Allpinyin.write(sh[n]+'\''+un[n]+'\t')
            n += 1
        Allpinyin.write('\n')

# 提取含飞键的词组到 jdf.csv，以便另外处理
# 将全拼词组变为列表
with open('pinyin.csv', 'r', encoding='UTF-8') as file1:
    data1 = file1.readlines()
# 提取飞键
with open('jdf.csv', 'w', encoding='UTF-8') as file2:
    for line in data1:
        n = re.findall(r".*\t(ch'ao|ch'e|zh'ai|zh'ao|zh'e|ch'uang|g'uang|h'uang|k'uang|sh'uang|zh'uang)\t.*", line)
        if n:
            file2.writelines(line)

# 准备把全拼转成键道双拼
dict1 = {'\t\'':'\tx\'', '\tj\'u\t':'\tjl\t', '\tq\'u\t':'\tql\t', '\tx\'u\t':'\txl\t', '\ty\'u\t':'\tyl\t'} # 零声母引导
dict2 = {'\'iu\t':'q\t', '\'ua\t':'q\t', '\'ei\t':'w\t', '\'un\t':'w\t', '\'e\t':'e\t', '\'eng\t':'r\t', '\'uan\t':'t\t', '\'iong\t':'y\t', '\'ong\t':'y\t', '\'ang\t':'p\t', '\'a\t':'s\t', '\'ia\t':'s\t', '\'ie\t':'d\t', '\'ou\t':'d\t', '\'an\t':'f\t', '\'ing\t':'g\t', '\'uai\t':'g\t', '\'ai\t':'h\t', '\'ue\t':'h\t', '\'ve\t':'h\t', '\'er\t':'j\t', '\'u\t':'j\t', '\'i\t':'k\t', '\'o\t':'l\t', '\'uo\t':'l\t', '\'v\t':'l\t', '\'ao\t':'z\t', '\'iang\t':'x\t', '\'iao\t':'c\t', '\'in\t':'b\t', '\'ui\t':'b\t', '\'en\t':'n\t', '\'n\t':'n\t', '\'ian\t':'m\t'} # 韵母
dicta = {'\tch':'\tj', '\tzh':'\tq', '\tsh':'\te', '\'uang':'m'} # 飞键1
dictb = {'\tch':'\tw', '\tzh':'\tf', '\tsh':'\te', '\'uang':'x'} # 飞键2

# 把词组列表转换为字符串
allPY = "".join(data1)
# 先将特殊编码及零声母搞定
for k, v in dict1.items():
    allPY = allPY.replace(k, v)
# 固定飞键替换
allPY = re.sub("\t(ch)(\')(ai|an|ang|en|eng|u|un)\t", r"\tj\2\3\t", allPY)
allPY = re.sub("\t(ch)(\')(a|i|ong|ou|ua|uai|uan|uang|ui|uo)\t", r"\tw\2\3\t", allPY)
allPY = re.sub("\t(zh)(\')(an|ang|ei|en|eng|u|un)\t", r"\tq\2\3\t", allPY)
allPY = re.sub("\t(zh)(\')(a|i|ong|ou|ua|uai|uan|uang|ui|uo)\t", r"\tf\2\3\t", allPY)
# 飞键1替换
for k, v in dicta.items():
    allPY = allPY.replace(k, v)
# 韵母替换
for k, v in dict2.items():
    allPY = allPY.replace(k, v)
# 将键道音码存入 jdy.csv 文件
with open('jdy.csv', 'w', encoding='UTF-8') as file2:
    file2.write(allPY)

# 不管了，直接飞键再运行一遍
with open('jdf.csv', 'r', encoding='UTF-8') as file3:
    data3 = file3.readlines()
allPYf = "".join(data3)
# # 先将特殊编码及零声母搞定
for k, v in dict1.items():
    allPYf = allPYf.replace(k, v)
# # 固定飞键替换
allPYf = re.sub("\t(ch)(\')(ai|an|ang|en|eng|u|un)\t", r"\tj\2\3\t", allPYf)
allPYf = re.sub("\t(ch)(\')(a|i|ong|ou|ua|uai|uan|uang|ui|uo)\t", r"\tw\2\3\t", allPYf)
allPYf = re.sub("\t(zh)(\')(an|ang|ei|en|eng|u|un)\t", r"\tq\2\3\t", allPYf)
allPYf = re.sub("\t(zh)(\')(a|i|ong|ou|ua|uai|uan|uang|ui|uo)\t", r"\tf\2\3\t", allPYf)
# # 飞键2替换
for k, v in dictb.items():
    allPYf = allPYf.replace(k, v)
# # 韵母替换
for k, v in dict2.items():
    allPYf = allPYf.replace(k, v)
# # 将键道音码存入 jdy.csv 文件
with open('jdyf.csv', 'w', encoding='UTF-8') as file4:
    file4.write(allPYf)

# 输出音形码
with open('jdy.csv', 'r+', newline="", encoding='UTF-8') as csvf:
    with open('jdAll.csv', 'w', encoding='UTF-8') as jda:
        rows = csv.reader(csvf, dialect=csv.excel_tab)
        for row in rows:
            if len(row) <= 4:
                try:
                    sy1 = row[1][:2]
                    sy2 = row[2][:2]
                except:
                    print(row)
                    continue
                jda.write(row[0]+'\t'+sy1+sy2+'\n')
            elif len(row) <= 5:
                try:
                    s1 = row[1][:1]
                    s2 = row[2][:1]
                    s3 = row[3][:1]
                except:
                    print(row)
                    continue
                jda.write(row[0]+'\t'+s1+s2+s3+'\n')
            else:
                try:
                    s1 = row[1][:1]
                    s2 = row[2][:1]
                    s3 = row[3][:1]
                    s4 = row[-2][:1]
                except:
                    print(row)
                    continue
                jda.write(row[0]+'\t'+s1+s2+s3+s4+'\n')
            # print(row)

# 追加飞键
with open('jdyf.csv', 'r+', newline="", encoding='UTF-8') as csvf:
    with open('jdAll.csv', 'a', encoding='UTF-8') as jda:
        jda.write('\n'+'# =========以下是飞键========='+'\n')
        rows = csv.reader(csvf, dialect=csv.excel_tab)
        for row in rows:
            if len(row) <= 4:
                try:
                    sy1 = row[1][:2]
                    sy2 = row[2][:2]
                except:
                    print(row)
                    continue
                jda.write(row[0]+'\t'+sy1+sy2+'\n')
            elif len(row) <= 5:
                try:
                    s1 = row[1][:1]
                    s2 = row[2][:1]
                    s3 = row[3][:1]
                except:
                    print(row)
                    continue
                jda.write(row[0]+'\t'+s1+s2+s3+'\n')
            else:
                try:
                    s1 = row[1][:1]
                    s2 = row[2][:1]
                    s3 = row[3][:1]
                    s4 = row[-2][:1]
                except:
                    print(row)
                    continue
                jda.write(row[0]+'\t'+s1+s2+s3+s4+'\n')
            # print(row)

# 去除追加飞键中对编码无影响的三词及以上的 'uang'
data4 = pandas.read_csv('jdAll.csv', dialect=csv.excel_tab, encoding='UTF-8')
data5 = data4.drop_duplicates(keep='first', inplace=False)
data5.to_csv('jdAll.csv', index=None, sep='\t', encoding='UTF-8')

# 将首笔对应码转为字典
dictx = {}
with open('jdx.csv', 'r+', encoding='UTF-8') as f:
    reader=csv.reader(f, dialect=csv.excel_tab)
    for row in reader:
        dictx[row[0]]=row[1]

# 开始添加形码，最核心、最常用的词库可以不加形码以降低码长
# 把音码存为列表
with open('jdAll.csv', 'r', encoding='UTF-8') as file:
    datax = file.readlines()

# 添加形码
with open('jdAllx.csv', 'w', encoding='UTF-8') as jdAllx:
    for cizu in datax:
        if len(cizu)==8 and cizu[2]!='\t':
            try:
                x1 = dictx[cizu[0]]
                x2 = dictx[cizu[1]]
                x3 = dictx[cizu[2]]
                jdAllx.write(cizu[:-1] + x1 + x2 + x3 + '\n')
            except Exception as e:
                # 终端可能会输出一些字，已 pass 说明这些字不在 py2jd/jdx.csv 中，如果确实需要该字，自行添加至 py2jd/jdx.csv，并加入第一笔的笔画码。
                pass
        elif len(cizu)==27: # 飞键分割线
            jdAllx.write(cizu)
        else :
            try:
                x1 = dictx[cizu[0]]
                x2 = dictx[cizu[1]]
                jdAllx.write(cizu[:-1] + x1 + x2 + '\n')
            except Exception as e:
                # 终端可能会输出一些字，已 pass 说明这些字不在 py2jd/jdx.csv 中，如果确实需要该字，自行添加至 py2jd/jdx.csv，并加入第一笔的笔画码。
                pass

#####################
### Added by Ivan ###
#####################

pattern = r'^.*\t[a-z]*'
output_zc_file = "./已有字词.txt"
output_bm_file = "./已有编码.txt"

# 1. 获取已有的编码和字词
file_list = [output_zc_file, output_bm_file]
for file in file_list:
    if os.path.exists(file):
        os.remove(file)

# 打开输出文件
with open(output_bm_file, 'w', encoding='utf-8') as outfile_ci, open(output_zc_file, 'w', encoding='utf-8') as outfile_bm:
    # 遍历目录下的所有yaml文件
    for filename in glob.glob('./*.dict.yaml'):
        # 打开yaml文件
        with open(filename, 'r', encoding='utf-8') as infile:
            # 读取yaml文件中的所有行
            lines = infile.readlines()
            # 遍历每一行，匹配正则表达式，将匹配结果写入输出文件
            for line in lines:
                if re.search(pattern, line):
                    outfile_bm.write(line.split("\t")[0]+"\n")
                    outfile_ci.write(line.split("\t")[1])

# 2. 读取 ./results/编码.txt 文件中的内容，存储在集合中
with open(output_bm_file, 'r', encoding='utf-8') as f:
    bm_set = set(line.strip() for line in f)

# 3. 读取 ./results/字词.txt 文件中的内容，存储在集合中
with open(output_zc_file, 'r', encoding='utf-8') as f:
    zc_set = set(line.strip() for line in f)

temp_set = set()
repe_set = set()
zc_repe_set = set()
bm_repe_set = set()

with open('jdAllx.csv', 'r', encoding='utf-8') as file:
    for line in file:
        # 先处理词库已有的字词，如果命中则整行跳过
        if line.split('\t')[0] in zc_set:
            continue

        line_bm = line.split('\t')[1].strip()

        # 处理词组 3 字, 3码空码动态匹配到 6 码
        if len(line.split('\t')[0].strip()) == 3:
            if line_bm[0:3] not in bm_set and line[0:3] not in zc_repe_set:
                zc_repe_set.add(line[0:3])
                if line_bm[0:3] not in bm_repe_set:
                    temp_set.add(line[:-4])
                    bm_repe_set.add(line_bm[0:3])
                elif line_bm[0:4] not in bm_repe_set:
                    temp_set.add(line[:-3])
                    bm_repe_set.add(line_bm[0:4])
                elif line_bm[0:5] not in bm_repe_set:
                    temp_set.add(line[:-2])
                    bm_repe_set.add(line_bm[0:5])
                elif line_bm[0:6] not in bm_repe_set:
                    temp_set.add(line[:-1])
                    bm_repe_set.add(line_bm[0:6])
            elif line_bm[0:4] not in bm_set and line[0:3] not in zc_repe_set:
                zc_repe_set.add(line[0:3])
                if line_bm[0:4] not in bm_repe_set:
                    temp_set.add(line[:-3])
                    bm_repe_set.add(line_bm[0:4])
                elif line_bm[0:5] not in bm_repe_set:
                    temp_set.add(line[:-2])
                    bm_repe_set.add(line_bm[0:5])
                elif line_bm[0:6] not in bm_repe_set:
                    temp_set.add(line[:-1])
                    bm_repe_set.add(line_bm[0:6])
            elif line_bm[0:5] not in bm_set and line[0:3] not in zc_repe_set:
                zc_repe_set.add(line[0:3])
                if line_bm[0:5] not in bm_repe_set:
                    temp_set.add(line[:-2])
                    bm_repe_set.add(line_bm[0:5])
                elif line_bm[0:6] not in bm_repe_set:
                    temp_set.add(line[:-1])
                    bm_repe_set.add(line_bm[0:6])
            elif line_bm[0:6] not in bm_set and line[0:3] not in zc_repe_set:
                zc_repe_set.add(line[0:3])
                if line_bm[0:6] not in bm_repe_set:
                    temp_set.add(line[:-1])
                    bm_repe_set.add(line_bm[0:6])
        # 处理其它长度的字词, 4码空码动态匹配到 6 码
        else:
            if line_bm[0:4] not in bm_set and line[0:4] not in zc_repe_set:
                zc_repe_set.add(line[0:4])
                if line_bm[0:4] not in bm_repe_set:
                    temp_set.add(line[:-3])
                    bm_repe_set.add(line_bm[0:4])
                elif line_bm[0:5] not in bm_repe_set:
                    temp_set.add(line[:-2])
                    bm_repe_set.add(line_bm[0:5])
                elif line_bm[0:6] not in bm_repe_set:
                    temp_set.add(line[:-1])
                    bm_repe_set.add(line_bm[0:6])
            elif line_bm[0:5] not in bm_set and line[0:4] not in zc_repe_set:
                zc_repe_set.add(line[0:4])
                if line_bm[0:5] not in bm_repe_set:
                    temp_set.add(line[:-2])
                    bm_repe_set.add(line_bm[0:5])
                elif line_bm[0:6] not in bm_repe_set:
                    temp_set.add(line[:-1])
                    bm_repe_set.add(line_bm[0:6])
            elif line_bm[0:6] not in bm_set and line[0:4] not in zc_repe_set:
                zc_repe_set.add(line[0:4])
                if line_bm[0:6] not in bm_repe_set:
                    temp_set.add(line[:-1])
                    bm_repe_set.add(line_bm[0:6])

content = '''---
name: xkjd6.result
version: "v1"
sort: original
...
'''

with open('./result.dict.yaml', 'w', encoding='utf-8') as outfile:
    outfile.write(content)
    for line in temp_set:
        outfile.write(line+"\n")