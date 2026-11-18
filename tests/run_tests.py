"""Run all checks from the project root; fixtures use disposable temporary directories."""
import os
import pathlib
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
lua = shutil.which('lua5.4') or shutil.which('lua')
luac = shutil.which('luac5.4') or shutil.which('luac')
if not lua or not luac:
    sys.exit('Lua 5.4 and luac are required')
for path in sorted((root / 'lua').rglob('*.lua')):
    subprocess.run([luac, '-p', str(path)], cwd=root, check=True)
for path in sorted((root / 'tests').glob('*_test.lua')):
    print(f'\n=== {path.name} ===', flush=True)
    env=os.environ.copy()
    if path.name=='stats_calendar_test.lua': env['TZ']='America/New_York'
    subprocess.run([lua, str(path)], cwd=root, check=True, env=env)
subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', '*_test.py'],
               cwd=root, check=True)
print('\nAll checks passed.', flush=True)
