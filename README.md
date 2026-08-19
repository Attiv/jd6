# 键道6·无飞键版

当前 Git 分支 `feature/xmjd6-nofly` 的仓库根目录就是无飞键方案，可直接作为 Rime 用户目录使用。

## 无飞键规则

- `ch → W`，例如超：`wz`、春：`wwv`。
- `zh → Q`，例如找：`qz`、中：`qy`。
- `uang → X`，例如光：`gx`、装：`qx`。
- 普通声母及其他韵母保持原规则，例如均：`jw`、无：`wj`、求：`qq`、服：`fj`。

内部方案标识仍是 `xmjd6`，所以飞键版和无飞键版不能在同一个 Rime 用户目录中同时启用。

## 在两种方案之间切换

切回原飞键版：

```bash
cd ~/Library/Rime
git checkout main
```

切到无飞键版：

```bash
cd ~/Library/Rime
git checkout feature/xmjd6-nofly
```

`installation.yaml` 和 `user.yaml` 是本机状态文件。可以保留其本地修改，但不要提交；如果 Git 提示它们阻止切换，应先自行备份或暂存。

## 切换后必须重新部署

Git 只切换源文件，`build/` 中可能仍是上一个分支的编译结果。因此每次切换分支后，都要在小狼毫或鼠须管菜单中执行**重新部署**。

macOS 也可以执行：

```bash
"/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_deployer" --build ~/Library/Rime
```

Windows 用户在小狼毫托盘菜单中选择“重新部署”即可。

## 验证当前版本

先确认分支和方案名：

```bash
git branch --show-current
grep 'name: 键道6·无飞键版' xmjd6.schema.yaml
python3 tests/test_nofly_root_layout.py
```

重新部署后实际输入：

| 输入 | 无飞键版应出现 | 旧飞键码不应再打出该字 |
| --- | --- | --- |
| `wz` | 超 | `jz` 不再对应“超” |
| `wwv` | 春 | `jwv` 不再对应“春” |
| `qz` | 找 | `fz` 不再对应“找” |
| `qy` | 中 | `fy` 不再对应“中” |
| `qx` | 装 | `fm`、`fx` 不再对应“装” |
| `gx` | 光 | `gm` 不再对应“光” |

再检查原生编码 `jw → 均`、`wj → 无`、`qq → 求`、`fj → 服` 仍然可用。

`conversion-report.txt` 记录真实词库的转换与去重统计。
