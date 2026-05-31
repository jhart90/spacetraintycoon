import re

with open('index.html', 'r', encoding='utf-8') as f:
    content = f.read()

scripts = re.findall(r'<script[^>]*>(.*?)</script>', content, re.DOTALL)
js = scripts[0]

lines = js.split('\n')
depth = 0
bracket_depth = 0
prev_depth = 0
for i, line in enumerate(lines):
    in_str = False
    sc = None
    for ch in line:
        if not in_str and ch in ("'", '"'):
            in_str = True; sc = ch
        elif in_str and ch == sc:
            in_str = False; sc = None
        elif not in_str:
            if ch == '(': depth += 1
            elif ch == ')': depth -= 1
            elif ch == '[': bracket_depth += 1
            elif ch == ']': bracket_depth -= 1
    if depth < 0 or bracket_depth < 0:
        print(f'Line {i+1}: paren_depth={depth} bracket_depth={bracket_depth}')
        print(f'  {repr(line[:150])}')
        break
    if depth != prev_depth and depth > 15:
        print(f'Line {i+1}: paren depth spike to {depth}: {repr(line[:100])}')
    prev_depth = depth

print(f'Final paren depth: {depth}')
print(f'Final bracket depth: {bracket_depth}')
