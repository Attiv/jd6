def filter_dict_file(input_file_path, output_file_path, deleted_words_file_path):
    with open(input_file_path, 'r', encoding='utf-8') as file:
        lines = file.readlines()

    with open(output_file_path, 'w', encoding='utf-8') as output_file, \
         open(deleted_words_file_path, 'w', encoding='utf-8') as deleted_words_file:
        for line in lines:
            # 通过分隔空格提取汉字部分
            word_parts = line.split('\t')
            if len(word_parts) > 0:
                word = word_parts[0]
                # 检查是否超过4个汉字
                if len(word) > 4:
                    # 将超过4个汉字的词写入删除文件
                    deleted_words_file.write(line)
                else:
                    # 将不超过4个汉字的词写入输出文件
                    output_file.write(line)

# 设置原始文件路径，输出文件路径和被删除词的保存文件路径
input_file_path = 'xkjd6.lanlao2.dict.yaml'
output_file_path = 'filtered_output_filename.yaml'
deleted_words_file_path = 'deleted_words_filename.txt'

# 调用函数
filter_dict_file(input_file_path, output_file_path, deleted_words_file_path)
