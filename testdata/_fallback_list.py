# Regenerate testdata/fallback_current.md — the list of (tid, category) whose
# main draw could not be rendered as a bracket tree, grouped by likely cause.
import json, glob, re, os

RL = {0: 'Final', 1: 'SF', 2: 'QF', 3: 'R16', 4: 'R32', 5: 'R64', 6: 'R128', 7: 'R256',
      -1: '无标签/小组赛', 12: 'QR4', 13: 'QR8', 14: 'QR16', 15: 'QR32', 16: 'QR64'}
QUAL_RE = re.compile(r'Qualif|Qualifying|WTTC Continental Stage')

fb, nomn = [], []
for f in glob.glob('web/data/events/*.json'):
    tid = int(os.path.basename(f)[:-5])
    d = json.load(open(f, encoding='utf-8'))
    for cat in ('MS', 'WS'):
        p = d.get(cat)
        if not p:
            continue
        if 'r' in p:
            codes = {}
            for code, rows in p['r']:
                codes[RL.get(code, str(code))] = len(rows)
            fb.append((tid, d['n'], d['e'], cat, codes))
        elif 't' not in p:
            nomn.append((tid, d['n'], d['e'], cat, len(p.get('q', []))))
fb.sort(key=lambda r: (r[2], r[0]))
nomn.sort(key=lambda r: (r[2], r[0]))
sec_a = [r for r in fb if QUAL_RE.search(r[1])]
sec_b = [r for r in fb if not QUAL_RE.search(r[1])]

out = ['# 当前无法生成对阵图的赛事清单', '',
       '生成自 web/data/events/*.json（testdata/_fallback_list.py 可重新生成）。'
       f'分栏回退 {len(fb)} 类，无主赛制数据 {len(nomn)} 类。', '']
out.append(f'## 一、预选赛性质，保持分栏（{len(sec_a)} 类）')
out.append('')
for tid, n, e, cat, codes in sec_a:
    out.append(f'- [{tid}] {n}（{e[:7]}，{cat}）' + '，'.join(f'{k}×{v}' for k, v in codes.items()))
out += ['', f'## 二、非预选赛，待进一步排查（{len(sec_b)} 类）', '']
for tid, n, e, cat, codes in sec_b:
    out.append(f'- [{tid}] {n}（{e[:7]}，{cat}）' + '，'.join(f'{k}×{v}' for k, v in codes.items()))
out += ['', f'## 三、主赛制数据缺失（仅有资格赛/小组赛行，{len(nomn)} 类）', '']
for tid, n, e, cat, qn in nomn:
    out.append(f'- [{tid}] {n}（{e[:7]}，{cat}）资格赛/其他 {qn} 场')
open('testdata/fallback_current.md', 'w', encoding='utf-8').write('\n'.join(out))
print('written testdata/fallback_current.md:',
      len(sec_a), 'qualifier,', len(sec_b), 'non-qualifier fallback,', len(nomn), 'no-main')
