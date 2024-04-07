# xmjd6.fjcy.dict_modified.yaml 去掉右边的编码
with open('xmjd6.fjcy.dict.yaml', 'r') as input_file, \
     open('xmjd6.fjcy.dict_modified.yaml', 'w') as output_file:
    for line in input_file:
        word = line.split()[0]
        output_file.write(word + '\n')