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
- 如果多个词都会缩到同一个短码，也不自动处理，放到冲突列表里。
- 默认只生成报告，不改词库。

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

## 进阶：循环缩码到不能再缩

如果一个 6 位码先缩成 5 位后，新的 5 位码还可以继续缩成 4 位，可以加 `--repeat` 让脚本自动重复扫描/写回，直到没有安全缩码为止：

```bash
python3 shrink_empty_codes.py \
  --report shrink_empty_codes_report_main.txt \
  --exclude 'english.dict.yaml' \
  --exclude 'pinyin_simp.dict.yaml' \
  --exclude 'liangfen.dict.yaml' \
  --exclude 'xmjd6.en.dict.yaml' \
  --exclude 'xmjd6.gbk.dict.yaml' \
  --apply \
  --repeat
```

推荐日常就用这一条。它仍然只处理安全项：

- 短码已经被占用：不缩。
- 多个词抢同一个短码：不缩。
- 本轮缩完后会重新全局扫描，再判断下一轮。

## 常用参数

| 参数 | 说明 |
|------|------|
| `--apply` | 实际写回词库；不加就是 dry-run |
| `--repeat` | 配合 `--apply` 循环缩码，直到没有安全项 |
| `--max-passes 20` | `--repeat` 的最大轮数，默认 20 |
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

脚本在 `--apply` 时会生成 `.bak` 备份。如果不需要，可以删除：

```bash
find . -name '*.bak' -type f -delete
```
