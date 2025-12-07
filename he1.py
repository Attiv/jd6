# script.py
import glob
import os

IMPORT_TABLE_FILE = 'xmjd6.extended.dict.yaml'


def load_import_order(path: str) -> list[str]:
    order = []
    in_import_tables = False
    with open(path, 'r', encoding='utf-8') as infile:
        for raw_line in infile:
            stripped = raw_line.strip()
            if not stripped:
                continue
            if stripped.startswith('import_tables:'):
                in_import_tables = True
                continue
            if not in_import_tables or stripped.startswith('#'):
                continue
            if stripped.startswith('- '):
                name = stripped[2:].split('#', 1)[0].strip()
                if name:
                    order.append(f'{name}.dict.yaml')
    return order


def should_skip(basename: str) -> bool:
    return (
        basename == 'pinyin_simp.dict.yaml'
        or basename.startswith('english')
        or basename.startswith('xmjd6.en')
        or basename == IMPORT_TABLE_FILE
    )


def iter_ordered_files() -> list[str]:
    files = glob.glob('./*.dict.yaml')
    order = load_import_order(IMPORT_TABLE_FILE)
    file_map = {
        os.path.basename(path): path
        for path in files
        if not should_skip(os.path.basename(path))
    }

    ordered_paths = []
    for fname in order:
        path = file_map.pop(fname, None)
        if path:
            ordered_paths.append(path)
    ordered_paths.extend(file_map.values())
    return ordered_paths


entries: dict[str, list[str]] = {}
for filename in iter_ordered_files():
    with open(filename, 'r', encoding='utf-8') as infile:
        for raw_line in infile:
            if raw_line.startswith(('#', '---', '...', 'name:', 'version:', 'sort:')):
                continue
            line = raw_line.strip()
            if not line or '\t' not in line:
                continue
            parts = [part.strip() for part in line.split('\t') if part.strip()]
            if len(parts) < 2:
                continue
            candidate, code = parts[0], parts[1]
            target = entries.setdefault(code, [])
            if candidate not in target:
                target.append(candidate)

with open('v6.txt', 'w', encoding='utf-8', newline='\n') as outfile:
    for code, candidates in entries.items():
        outfile.write('\t'.join([code] + candidates) + '\n')