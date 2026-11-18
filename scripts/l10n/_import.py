#!/usr/bin/env python3
"""把逐行译文（第 n 行对应 _keys.json 第 n 条）转成 <lang>.json。用法：python3 _import.py <lang> < lines.txt"""
import json, sys, os
here = os.path.dirname(os.path.abspath(__file__))
keys = json.load(open(os.path.join(here, '_keys.json'), encoding='utf-8'))
lines = sys.stdin.read().split('\n')
while lines and lines[-1] == '': lines.pop()
assert len(lines) == len(keys), f'{len(lines)} 行，应为 {len(keys)}'
json.dump(dict(zip(keys, lines)), open(os.path.join(here, sys.argv[1] + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(sys.argv[1], 'ok')
