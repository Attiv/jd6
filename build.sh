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
zip -r jd6.zip . -x "jd6_build.zip" -x "build/*" -x ".git/*" -x ".gitignore*" -x ".history/*" -x "build.sh" -x "兰佬转词库.zip" -x "词库转换键道.zip" -x "qui.py" -x ".scripts/*" -x "chongfu.py" -x ".build_back/*" -x ".build_back" -x "zhuyin.py" -x "user.yaml"

# move xmjd6enre.reverse.bin to build folder
mv build/xmjd6enre.reverse.bin build/

# add xmjd6enre.reverse.bin to the existing zip file
zip -ur jd6.zip build/xmjd6enre.reverse.bin


cp jd6.zip /Users/wanglikun/Library/Mobile\ Documents/com~apple~CloudDocs/jd6.zip
  echo "已创建 build.zip 压缩包。"