import re

with open('index.html', 'r', encoding='utf-8') as f:
    content = f.read()

scripts = re.findall(r'<script[^>]*>(.*?)</script>', content, re.DOTALL)
js = scripts[0]

# Properly skip strings and comments
def scan_js(js):
    i = 0
    n = len(js)
    depth_p = 0   # parens
    depth_b = 0   # brackets
    depth_c = 0   # braces
    issues = []
    while i < n:
        c = js[i]
        # Skip line comments
        if c == '/' and i+1 < n and js[i+1] == '/':
            while i < n and js[i] != '\n': i += 1
            continue
        # Skip block comments
        if c == '/' and i+1 < n and js[i+1] == '*':
            i += 2
            while i < n-1 and not (js[i]=='*' and js[i+1]=='/'): i += 1
            i += 2
            continue
        # Skip template literals
        if c == '`':
            i += 1
            while i < n and js[i] != '`':
                if js[i] == '\\': i += 1
                i += 1
            i += 1
            continue
        # Skip single-quoted strings
        if c == "'":
            i += 1
            while i < n and js[i] != "'":
                if js[i] == '\\': i += 1
                i += 1
            i += 1
            continue
        # Skip double-quoted strings
        if c == '"':
            i += 1
            while i < n and js[i] != '"':
                if js[i] == '\\': i += 1
                i += 1
            i += 1
            continue
        # Track depth
        if c == '(': depth_p += 1
        elif c == ')':
            depth_p -= 1
            if depth_p < 0:
                lineno = js[:i].count('\n') + 1
                issues.append(f'PAREN underflow at line {lineno}: ...{repr(js[max(0,i-60):i+60])}...')
                depth_p = 0
        elif c == '[': depth_b += 1
        elif c == ']':
            depth_b -= 1
            if depth_b < 0:
                lineno = js[:i].count('\n') + 1
                issues.append(f'BRACKET underflow at line {lineno}: ...{repr(js[max(0,i-60):i+60])}...')
                depth_b = 0
        elif c == '{': depth_c += 1
        elif c == '}':
            depth_c -= 1
            if depth_c < 0:
                lineno = js[:i].count('\n') + 1
                issues.append(f'BRACE underflow at line {lineno}: ...{repr(js[max(0,i-60):i+60])}...')
                depth_c = 0
        i += 1
    return depth_p, depth_b, depth_c, issues

p, b, c, issues = scan_js(js)
print(f'Final paren depth: {p}')
print(f'Final bracket depth: {b}')
print(f'Final brace depth: {c}')
if issues:
    print(f'\n{len(issues)} underflow issue(s):')
    for iss in issues[:10]:
        print(' ', iss)
else:
    print('\nNo underflows found.')
