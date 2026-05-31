import sys, json, subprocess, time

data = json.load(sys.stdin)
fp = data.get('tool_input', {}).get('file_path', '')
if 'build_game.py' not in fp:
    sys.exit(0)

result = subprocess.run(['git', 'log', '-1', '--format=%ct'], capture_output=True, text=True,
                        cwd=r'C:\Users\jackh\Desktop\Claude\Train Game')
if result.returncode != 0 or not result.stdout.strip():
    sys.exit(0)

elapsed = time.time() - int(result.stdout.strip())
if elapsed <= 3600:
    sys.exit(0)

cwd = r'C:\Users\jackh\Desktop\Claude\Train Game'
subprocess.run(['git', 'add', '-A'], cwd=cwd)
subprocess.run(['git', 'commit', '-m', f'Auto-checkpoint before build_game.py edit ({elapsed/3600:.1f}h since last commit)'], cwd=cwd)
subprocess.run(['git', 'push'], cwd=cwd)

print(json.dumps({'systemMessage': f'Auto-checkpoint committed to GitHub ({elapsed/3600:.1f}h since last commit)'}))
