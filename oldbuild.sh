#!/bin/bash

file="jd6_old.zip"

if [ -f "$file" ]; then
    echo "Deleting $file..."
    rm "$file"
    echo "$file deleted."
else
    echo "$file not found."
fi

# create the zip file
zip -vr jd6_old.zip . -x "jd6_build.zip" -x "build/*" -x ".git/*" -x ".gitignore*" -x "sync/*" -x ".history/*" -x "build.sh" -x "兰佬转词库.zip" -x "词库转换键道.zip" -x "qui.py" -x ".scripts/*" -x "chongfu.py" -x ".build_back/*" -x ".build_back" -x "zhuyin.py" -x "jd6_irime.zip" -x "jd6.zip" -x "jd6_old.zip"


file_path="user.yaml"

if [ -f "$file_path" ]; then
    # 使用sed替换tofu的值
    sed -i '/^ *tofu:/s/false/true/' "$file_path"
    echo "tofu的值已设置为true"
else
    echo "文件 $file_path 不存在"
fi