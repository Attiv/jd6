# xmjd6.fjcy.dict_modified.yaml 去掉右边的编码
# xmjd6.fjcy.dict_modified.yaml
import traceback
try:
    with open('xmjd6.fjcy.dict.yaml', 'r') as input_file, \
         open('xmjd6.fjcy.dict_modified.yaml', 'w') as output_file:
        for line_no, line in enumerate(input_file, start=1):
            # Skip empty lines
            if not line.strip():
                continue
            try:
                word = line.split()[0]
                output_file.write(word + '\n')
            except IndexError:
                print(f"Error on line {line_no}: cannot split line into word and code. Original line: '{line.strip()}'")
except Exception as e:
    traceback.print_exc()