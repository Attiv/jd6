#!/bin/bash

file="jd6_build.zip"

if [ -f "$file" ]; then
    echo "Deleting $file..."
    rm "$file"
    echo "$file deleted."
else
    echo "$file not found."
fi

# 检查是否存在build文件夹
if [ -d "build" ]; then
  # 压缩build文件夹为一个zip文件
  zip -r jd6_build.zip . -x ".git/*" -x ".gitignore*" -x ".history/*" -x "build.sh" -x "词库转换键道.zip" -x "qui.py" -x ".scripts/*" -x "chongfu.py" -x "*dict.yaml" -x ".build_back/*" -x "兰佬转词库.zip" -x "jd6.zip"
  echo "已创建 build.zip 压缩包。"
else
  echo "当前目录下不存在 build 文件夹。"
fi

cp jd6_build.zip /Users/mac/Library/Mobile\ Documents/com~apple~CloudDocs/jd6_build.zip
