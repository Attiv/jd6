# shrink_empty_codes.py 使用说明

这个脚本用于扫描 Rime 词库里的编码，找出可以“缩短一位”的词条。

例如：

```txt
某词    xkjdo
```

如果 `xkjd` 在所有被扫描词库里都没有被占用，脚本会认为它可以缩成：

```txt
某词    xkjd
```

## 安全规则

脚本只处理真正空码：

- 只考虑长度大于等于 5 的编码。
- 每次只缩短最后 1 位。
- 如果短一码已经存在，不处理。
- 如果多个词本来就共用同一个旧码，会作为一组整体缩到同一个空短码。
- 如果多个不同旧码都会缩到同一个短码，不自动处理，放到冲突列表里。
- 默认只生成报告，不改词库。
- 新版脚本默认不生成 `.bak`；只有加 `--backup` 才生成。

## 只看报告，不修改词库

全量扫描当前目录下所有 `*.dict.yaml`：

```bash
python3 shrink_empty_codes.py
```

生成报告：

```txt
shrink_empty_codes_report.txt
```

## 推荐：扫描主词库，排除英文/拼音/GBK

新版脚本可以直接用 `--main`：

```bash
python3 shrink_empty_codes.py --main --report shrink_empty_codes_report_main.txt
```

等价于下面这一长串排除参数：

```bash
python3 shrink_empty_codes.py \
  --report shrink_empty_codes_report_main.txt \
  --exclude 'english.dict.yaml' \
  --exclude 'pinyin_simp.dict.yaml' \
  --exclude 'liangfen.dict.yaml' \
  --exclude 'xmjd6.en.dict.yaml' \
  --exclude 'xmjd6.gbk.dict.yaml'
```

生成报告：

```txt
shrink_empty_codes_report_main.txt
```

## 实际修改词库

确认报告没问题后，加 `--apply`：

```bash
python3 shrink_empty_codes.py \
  --report shrink_empty_codes_report_main.txt \
  --exclude 'english.dict.yaml' \
  --exclude 'pinyin_simp.dict.yaml' \
  --exclude 'liangfen.dict.yaml' \
  --exclude 'xmjd6.en.dict.yaml' \
  --exclude 'xmjd6.gbk.dict.yaml' \
  --apply
```

`--apply` 只会修改安全候选项，不会修改冲突项。

## 检查是否还有遗留空码

如果之前已经跑过一次 `--apply`，还可能出现这种情况：

1. 第一轮把 `abcdef` 缩成 `abcde`。
2. 原来的 `abcdef` 码位被释放。
3. 如果还有 `abcdefg`，它现在又可以缩成 `abcdef`。

所以要检查是否还有遗留空码，重新 dry-run 一次：

```bash
python3 shrink_empty_codes.py --main --report shrink_empty_codes_report_remaining.txt
```

等价于：

```bash
python3 shrink_empty_codes.py \
  --report shrink_empty_codes_report_remaining.txt \
  --exclude 'english.dict.yaml' \
  --exclude 'pinyin_simp.dict.yaml' \
  --exclude 'liangfen.dict.yaml' \
  --exclude 'xmjd6.en.dict.yaml' \
  --exclude 'xmjd6.gbk.dict.yaml'
```

看报告头部：

```txt
safe_candidates: 0
```

如果不是 0，说明还有可以安全缩码的词条。

## 多轮缩码直到没有安全候选

要自动处理这种“缩完一轮又释放下一轮”的情况，用 `--repeat`：

```bash
python3 shrink_empty_codes.py \
  --main \
  --report shrink_empty_codes_report_remaining.txt \
  --apply \
  --repeat
```

等价于：

```bash
python3 shrink_empty_codes.py \
  --report shrink_empty_codes_report_remaining.txt \
  --exclude 'english.dict.yaml' \
  --exclude 'pinyin_simp.dict.yaml' \
  --exclude 'liangfen.dict.yaml' \
  --exclude 'xmjd6.en.dict.yaml' \
  --exclude 'xmjd6.gbk.dict.yaml' \
  --apply \
  --repeat
```

如果你临时想要 `.bak`，再额外加：

```bash
--backup
```

## 常用参数

| 参数 | 说明 |
|------|------|
| `--apply` | 实际写回词库；不加就是 dry-run |
| `--repeat` | 配合 `--apply`，多轮缩码直到没有安全候选 |
| `--backup` | 配合 `--apply`，修改前生成 `.bak`；默认不生成 |
| `--main` | 使用推荐主词库范围，自动排除英文/拼音/GBK |
| `--report 文件名` | 指定报告文件名 |
| `--glob '*.dict.yaml'` | 指定要扫描的词库 glob，可重复使用 |
| `--exclude '文件名或glob'` | 排除词库，可重复使用 |
| `--min-length 5` | 只处理至少这么长的编码，默认 5 |

## 看报告

```bash
less shrink_empty_codes_report_main.txt
```

报告里主要看两段：

- `SAFE CANDIDATES`：可以安全缩码的词条。
- `CONFLICTS`：多个词抢同一个短码，脚本不会自动改。

## 删除 .bak

如果旧版脚本或手动操作产生了 `.bak`，可以删除：

```bash
find . -name '*.bak' -type f -delete
```

## 保护手工补码

如果某个词虽然还能按脚本规则继续缩码，但你想保留手工指定编码，可以写进：

```txt
shrink_empty_codes_protect.txt
```

格式是一行一个：

```txt
词语<TAB>编码
```

例如：

```txt
两委干部	lxgbvu
```

脚本默认会读取这个保护文件。要禁用保护文件，可以加：

```bash
--protect ''
```
