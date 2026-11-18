#!/usr/bin/env python3
"""从源码收集中文文案键，按 scripts/l10n/<lang>.json 生成 Resources/Localization/<lang>.lproj/Localizable.strings，
并校验：缺失的键、多余的键、占位符（%@ %%）不一致。用法：python3 scripts/gen_strings.py [--check]"""
import re, glob, json, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lit = re.compile(r'"((?:[^"\\]|\\.)*)"')

def collect():
    keys = []
    for f in sorted(glob.glob(os.path.join(ROOT, 'Sources/BetterWacom/*.swift'))):
        if f.endswith(('Snapshot.swift', 'Localization.swift')): continue
        for line in open(f, encoding='utf-8'):
            st = line.strip()
            if st.startswith('//') or 'NSLog(' in line: continue
            for m in lit.finditer(line):
                t, pre = m.group(1), line[:m.start()]
                if '//' in pre and pre.rfind('//') > pre.rfind('"') and pre.count('"') % 2 == 0: break
                if re.search(r'[\u4e00-\u9fff]', t) and '\\(' not in t and t not in keys: keys.append(t)
    # 手工补充（不在 Swift 字面量里直接出现的）
    for k in ["语言", "跟随系统", "重新启动以应用语言"]:
        if k not in keys: keys.append(k)
    return keys

def ph(s): return sorted(re.findall(r'%(?:@|%|\d+\$@)', s))

def esc(s): return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

def main():
    keys = collect()
    json.dump(keys, open(os.path.join(ROOT, 'scripts/l10n/_keys.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    ok = True
    for path in sorted(glob.glob(os.path.join(ROOT, 'scripts/l10n/*.json'))):
        lang = os.path.basename(path)[:-5]
        if lang.startswith('_'): continue
        tr = json.load(open(path, encoding='utf-8'))
        missing = [k for k in keys if k not in tr]
        extra = [k for k in tr if k not in keys]
        bad = [k for k in keys if k in tr and ph(k) != ph(tr[k])]
        if missing or bad:
            ok = False
        print(f'{lang}: {len(keys) - len(missing)}/{len(keys)}' + (f'  缺 {len(missing)}' if missing else '') +
              (f'  占位符不一致 {bad}' if bad else '') + (f'  多余 {len(extra)}' if extra else ''))
        if '--check' in sys.argv: continue
        d = os.path.join(ROOT, f'Resources/Localization/{lang}.lproj'); os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, 'Localizable.strings'), 'w', encoding='utf-8') as out:
            for k in keys:
                if k in tr:
                    # 源码里的键已经是转义过的形式（如 \"），原样写入
                    out.write(f'"{k}" = "{esc(tr[k])}";\n')
    # 源语言：键即译文
    d = os.path.join(ROOT, 'Resources/Localization/zh-Hans.lproj'); os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'Localizable.strings'), 'w', encoding='utf-8') as out:
        for k in keys: out.write(f'"{k}" = "{k}";\n')
    sys.exit(0 if ok else 1)

main()
