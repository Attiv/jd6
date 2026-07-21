# candidate_order 调频使用说明

用途：把后面的候选提到前面的编码，同时把被挤下来的词按键道6规则顺势补码。

## 1. 运行时调频：改 `candidate_order.txt`

文件位置：Rime 用户目录下的 `candidate_order.txt`。

格式一行一条，**推荐用 Tab 分隔**：

```text
提到前面的词<Tab>它原来的码<Tab>被挤下来的词<Tab>目标码<Tab>被挤词补码
```

例子：

```text
边骂	bmmsa	编码	bmms	bmmsa
词频	ckpbo	次品	ckpb	ckpbo
```

效果：

```text
bmms   -> 边骂        # 边骂从 bmmsa 提到 bmms
bmmsa  -> 编码        # 编码按键道6二字词规则补一位

ckpb   -> 词频
ckpbo  -> 次品
```

改完 `candidate_order.txt` 后，Lua 会按文件修改时间自动重载；**日常增删这份文件不需要重新部署**。

> 第一次安装这个功能时，因为 schema 新增了 translator/filter，需要重新部署一次。之后只同步/修改 `candidate_order.txt` 即可。


## 1.1 打字时一键调频

操作流程：

1. 正常输入目标码，例如 `bmms`。
2. 用方向键/翻页/数字选择，如果要调第二候选，不用高亮；如果要调其他候选，就先把它高亮。
   - iOS / Android 自研键盘：长按候选可移动高亮，不会直接提交候选。
3. 按 `0`。
4. 第二候选（或当前高亮候选）会写入 `candidate_order.txt`，并把原首选作为被挤词记录下来；会同时写入被挤词补码，避免下次输入时临时算码卡顿。即使提上来的词与原首选同码（例如自造词和原词同码），也会尽量给被挤词补码。
5. 如果首选已经是调频提上来的词，再对被挤下来的候选按 `0`，会撤销这条调频记录；不会追加一条反向同码记录。
6. 重新输入同一个编码，就能看到新顺序。

例：输入 `bmms`，首选是“编码”，第二候选是“边骂”；直接按 `0`，会自动追加：

```text
边骂	bmmsa	编码	bmms	bmmsa
```

之后：

```text
bmms  -> 边骂
bmmsa -> 编码
```

动态调频总开关默认开启，switcher 里会显示“调频开/调频关”。切到“调频关”后，`0` 不再调频，也不显示/隐藏 `candidate_order.txt` 里的调频记录。

如果想在配置里硬关，也可以写：

```yaml
patch:
  candidate_order/enabled: false
```

多端同步时，iOS、Android 和 Mac 小企鹅 WebDAV 同步入口会同时处理 `dynamic_phrases.txt` 和 `candidate_order.txt`；调频记录只需要同步 `candidate_order.txt`，不用同步固化词库。

热键可在 `xmjd6.schema.yaml` 里改：

```yaml
candidate_order:
  hotkey: "0"
```

## 2. 规则说明

Lua 不重新拆字，而是读取现有 `xmjd6.cx.dict.yaml` / `xmjd6.danzi.dict.yaml` 里的单字全码，再按键道6词组规则生成被挤词的新码：

- 二字词：`第1字音码2位 + 第2字音码2位 + 第1字形首码 + 第2字形首码`
- 三字词：`第1字声 + 第2字声 + 第3字声 + 三字形首码`
- 四字及以上：`第1字声 + 第2字声 + 第3字声 + 末字声 + 第1字形首码 + 第2字形首码`

例如：

```text
编码：编 bmaaoa + 码 msvuaa => bmmsav
边骂：边 bmauoa + 骂 msooaa => bmmsao
```

所以把 `边骂 bmmsa` 提到 `bmms` 时，`编码 bmms` 会先补到 `bmmsa`。

补码会按全码从短到长尝试，尽量避开已有静态词、自造词和其他调频记录：

```text
目标码 + 1 位 -> 目标码 + 2 位 -> ... -> 全码
```

如果短补码已经被其他词占用，会继续往后补。

运行时按 `0` 时只扫描本次可能用到的候选补码，不会为全词库建立完整占用表；正常打字不受影响。

## 3. 固化到词库

在电脑上运行：

```bash
python3 scripts/apply_candidate_order.py --dry-run
```

确认输出没问题后执行：

```bash
python3 scripts/apply_candidate_order.py --apply
```

脚本会：

1. 读取 `candidate_order.txt`
2. 生成 `xmjd6.candidate_order.dict.yaml`
3. 从原词库中移除被调频影响的旧词条
4. 之后需要重新部署一次，让固化词库生效

如果确认本次记录已经固化，想自动备份并清空 `candidate_order.txt`，使用：

```bash
python3 scripts/apply_candidate_order.py --apply --clear-order
```

脚本会先把当前 `candidate_order.txt` 备份为同目录下的
`candidate_order.txt.YYYYMMDD-HHMMSS.bak`，再只保留表头。这样
`candidate_order.txt` 后续只存新的、尚未固化的运行时调频记录。

如果只想生成固化词库，不想删原词库：

```bash
python3 scripts/apply_candidate_order.py --apply --no-remove
```

## 4. 调试

如果某一行格式写错，输入：

```text
coerr
```

会以候选形式显示 `candidate_order.txt` 的解析错误。
