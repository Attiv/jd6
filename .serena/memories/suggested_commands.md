# Suggested commands for Rime

- List files: `ls -la`
- Search files: `rg --files`
- Search content: `rg "pattern"`
- Read files: `sed -n '1,200p' <file>`
- Build package: `bash build.sh`
- Build alternate package: `bash bbuild.sh`
- Generate dictionary data from README workflow: `python3 py2jd.py`
- Inspect git status: `git status --short`
- Inspect recent commits: `git log --oneline -5`

Notes:
- The system is Darwin/macOS.
- Packaging scripts may copy archives to an iCloud Drive path under `/Users/mac/Library/Mobile Documents/`.
