#!/bin/bash

file="jd6.zip"

if [ -f "$file" ]; then
    echo "Deleting $file..."
    rm "$file"
    echo "$file deleted."
else
    echo "$file not found."
fi

# create the zip file
mkdir iRime && rsync -av --progress ./* iRime/ --exclude jd6_build.zip --exclude build --exclude .git --exclude .gitignore --exclude .history --exclude build.sh --exclude 兰佬转词库.zip --exclude 词库转换键道.zip --exclude qui.py --exclude .scripts --exclude chongfu.py --exclude .build_back --exclude zhuyin.py --exclude jd6_irime.zip --exclude jd6.zip && zip -r jd6.zip iRime/ && rm -rf iRime/


file_path="user.yaml"

if [ -f "$file_path" ]; then
    # 使用sed替换tofu的值
    sed -i '/^ *tofu:/s/false/true/' "$file_path"
    echo "tofu的值已设置为true"
else
    echo "文件 $file_path 不存在"
fi

move xmjd6enre.reverse.bin to build folder
mv build/xmjd6enre.reverse.bin build/

add xmjd6enre.reverse.bin to the existing zip file
zip -ur jd6.zip build/xmjd6enre.reverse.bin


cp jd6.zip /Users/wanglikun/Library/Mobile\ Documents/com~apple~CloudDocs/jd6_irime.zip
  echo "已创建 build.zip 压缩包。"