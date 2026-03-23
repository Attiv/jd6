# Rime project overview

- Purpose: A local Rime input method configuration and dictionary workspace. The repository contains schemas, dictionaries, themes, Lua helpers, and packaging scripts for distributing zip archives.
- Main stack: YAML dictionary/schema files, Bash scripts, Python utilities, Lua helpers.
- Structure:
  - Repository root: most `.yaml`, `.dict.yaml`, `.schema.yaml`, and helper scripts.
  - `build/`: build artifacts.
  - `lua/`: Lua scripts used by Rime.
  - `theme/`, `pifu/`, `Fonts/`, `opencc/`: themes, skins, fonts, and OpenCC data.
  - `docs/`: documentation and plans.
- Packaging scripts: `build.sh` produces `jd6.zip`; `bbuild.sh` produces `jd6_build.zip`.
- README workflow: place personal dictionary files in the root, prepare input text, then run `python3 py2jd.py` to generate dictionary output.
