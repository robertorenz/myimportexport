# Builds the four MyImportExport volumes:
#
#   getting-started.html    install it, first export and import, the demos
#   programmers-guide.html  how it works, recipes, the Clarion notes
#   template-guide.html     every template, tab, prompt and embed point
#   reference.html          the class, the equates, the helper's command line
#
# Nothing in the reference is typed by hand.  The class members and equates are
# read out of libsrc\win\MyImportExport.inc, the template prompts and embeds out
# of template\win\MyImportExport.tpl/.tpw, and the helper's options out of
# helper\MIEConvert\Program.cs.  docs\usage.py says what each member is for and
# shows it in use; a member missing there fails the build.
#
# Run from the repository root:   python docs\build-docs.py
import io, re, html, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, os.path.join(ROOT, 'docs'))
from usage import PROPS, METHODS, EQUATES, OPTIONS

def _read(p, enc='cp1252'):
    return io.open(p, encoding=enc, newline='').read().replace('\r\n', '\n')

INC = _read('libsrc/win/MyImportExport.inc')
TPL = _read('template/win/MyImportExport.tpl')
TPW = _read('template/win/MyImportExport.tpw')
PRG = _read('helper/MIEConvert/Program.cs', 'utf-8-sig')

# ---------------------------------------------------------------- the class
def _extract_equates():
    out = []
    for m in re.finditer(r'^(MIE:\S+)\s+EQUATE\((\d+)\)\s*(?:!\s*(.*))?$', INC, re.M):
        out.append({'name': m.group(1), 'value': m.group(2), 'note': (m.group(3) or '').strip()})
    return out

def _extract_queues():
    out, lines = [], INC.split('\n')
    for i, l in enumerate(lines):
        m = re.match(r'^(MIE_\w+)\s+QUEUE,TYPE', l)
        if not m: continue
        doc = lines[i - 1].lstrip('! ').strip() if lines[i - 1].startswith('!') else ''
        fields, j = [], i + 1
        while lines[j].strip() != 'END':
            f = re.match(r'^(\w+)\s+(\S+)\s*(?:!\s*(.*))?$', lines[j])
            if f: fields.append({'name': f.group(1), 'type': f.group(2), 'note': (f.group(3) or '').strip()})
            j += 1
        out.append({'name': m.group(1), 'doc': doc, 'fields': fields})
    return out

def _extract_class():
    lines = INC.split('\n')
    a = next(i for i, l in enumerate(lines) if l.startswith('MyImportExportClass  CLASS'))
    b = next(i for i, l in enumerate(lines) if i > a and l.strip() == 'END')
    props, meths, group = [], [], 'Table and fields'
    for l in lines[a + 1:b]:
        g = re.match(r'^!\s*-+\s*(.+?)\s*-+\s*$', l)
        if g:
            group = g.group(1)[0].upper() + g.group(1)[1:]; continue
        m = re.match(r'^(\w+)\s+PROCEDURE(\(.*?\))?([^!]*?)\s*(?:!\s*(.*))?$', l)
        if m:
            attrs = m.group(3).strip(', ')
            meths.append({'name': m.group(1), 'parms': (m.group(2) or '')[1:-1], 'attrs': attrs,
                          'note': (m.group(4) or '').strip(), 'group': group,
                          'protected': 'PROTECTED' in attrs.upper()})
            continue
        m = re.match(r'^(\w+)\s+(\S+?)\s*(?:!\s*(.*))?$', l)
        if m:
            props.append({'name': m.group(1), 'type': m.group(2), 'note': (m.group(3) or '').strip(),
                          'group': group, 'protected': 'PROTECTED' in m.group(2).upper()})
    return props, meths

EQUATELIST = _extract_equates()
QUEUES     = _extract_queues()
PROPLIST, METHLIST = _extract_class()

# ---------------------------------------------------------------- the templates
def _args(s, i):
    """Split the argument list that starts at s[i] == '(' into top-level parts."""
    parts, depth, cur, q = [], 0, '', False
    while i < len(s):
        c = s[i]
        if q:
            cur += c
            if c == "'":
                if i + 1 < len(s) and s[i + 1] == "'": cur += "'"; i += 1
                else: q = False
        elif c == "'": q = True; cur += c
        elif c == '(':
            depth += 1
            if depth > 1: cur += c
        elif c == ')':
            depth -= 1
            if depth == 0: parts.append(cur.strip()); return parts, i
            cur += c
        elif c == ',' and depth == 1: parts.append(cur.strip()); cur = ''
        else: cur += c
        i += 1
    return parts, i

def _unq(s):
    s = s.strip()
    return s[1:-1].replace("''", "'") if len(s) >= 2 and s[0] == "'" and s[-1] == "'" else s

def _extract_templates():
    temps, cur, tab, box = [], None, '', ''
    for line in TPL.split('\n'):
        t = line.strip()
        m = re.match(r'#(EXTENSION|CONTROL|CODE)\(', t)
        if m:
            parts, _ = _args(t, t.index('('))
            cur = {'kind': m.group(1), 'name': parts[0], 'title': _unq(parts[1]), 'prompts': []}
            temps.append(cur); tab, box = '', ''; continue
        if cur is None: continue
        if t.startswith('#TAB('):    tab = _unq(_args(t, 4)[0][0]).replace('&&', '\x00').replace('&', '').replace('\x00', '&'); continue
        if t.startswith('#BOXED('):  box = _unq(_args(t, 6)[0][0]); continue
        if t.startswith('#ENDBOXED'): box = ''; continue
        if t.startswith('#PROMPT('):
            parts, end = _args(t, 7)
            rest = t[end + 1:]
            sym = re.match(r'\s*,\s*(%\w+)', rest)
            dflt = re.search(r'DEFAULT\((.*?)\)(?:,|$)', rest)
            ptype = parts[1] if len(parts) > 1 else ''
            pm = re.match(r"(DROP|FROM)\((.*)\)$", ptype)
            if pm and pm.group(1) == 'DROP': ptype = 'drop: ' + _unq(pm.group(2)).replace('|', ' | ')
            elif pm: ptype = 'from ' + pm.group(2)
            cur['prompts'].append({'label': _unq(parts[0]).replace('&', ''), 'type': ptype,
                                   'sym': sym.group(1) if sym else '',
                                   'default': _unq(dflt.group(1)) if dflt else '',
                                   'tab': tab, 'box': box})
    return temps

def _extract_embeds():
    out = []
    for m in re.finditer(r"#EMBED\((%\w+),'((?:[^']|'')*)'(.*?)TREE\('((?:[^']|'')*)'", TPW):
        out.append({'id': m.group(1), 'desc': m.group(2).replace("''", "'"),
                    'tree': m.group(4).replace("''", "'").split('|'),
                    'perfile': ',%File' in m.group(3)})
    return out

TEMPLATES = _extract_templates()
EMBEDS    = _extract_embeds()
TPLVER    = re.search(r"#TEMPLATE\(MyImportExport,'([^']*)'", TPL).group(1)
BUILDTAG  = re.search(r"#DISPLAY\('MyImportExport template build ([^']*)'\)", TPL).group(1)

# ---------------------------------------------------------------- the helper
def _extract_helper():
    usage = re.search(r'Usage\s*=\s*(.*?);', PRG, re.S).group(1)
    usage = ''.join(re.findall(r'"((?:[^"\\]|\\.)*)"', usage)).replace('\\r\\n', '\n').strip()
    body = PRG[PRG.index('static Options Parse'):]
    body = body[:body.index('\n        static ', 10)]
    opts = re.findall(r'case "(\w+)"', body)
    return usage, opts

HELPER_USAGE, HELPER_OPTS = _extract_helper()

MISSING = []

# ---------------------------------------------------------------- helpers
def esc(s): return html.escape(s or '')
def slug(s): return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')

def code(txt, lang='clarion'):
    return '<pre class="code" data-lang="%s"><code>%s</code></pre>' % (lang, esc(txt.strip('\n')))

def usecode(txt):
    return '<pre class="code code--use" data-lang="use"><code>%s</code></pre>' % esc(txt)

def note(kind, title, body):
    return ('<aside class="note note--%s"><p class="note__t">%s</p><div class="note__b">%s</div></aside>'
            % (kind, esc(title), body))

def table(head, rows, cls=''):
    th = ''.join('<th>%s</th>' % h for h in head)
    tr = ''.join('<tr>%s</tr>' % ''.join('<td>%s</td>' % c for c in r) for r in rows)
    return ('<div class="tw"><table class="%s"><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>'
            % (cls, th, tr))

# ---------------------------------------------------------------- volumes
VOLUMES = [
 ('getting-started.html',   'Getting Started',      'Install it and move your first table'),
 ('programmers-guide.html', "Programmer's Guide",   'How it works, and how to make it do things'),
 ('template-guide.html',    'Template Guide',       'Every template, tab, prompt and embed'),
 ('reference.html',         'Reference',            'The class, the equates and the helper'),
]

#  Published, each volume is its own page on its own address, so a relative
#  filename does not reach the next one.  Cross-volume links are written as
#  these absolute addresses; the local copies in docs/ therefore point at the
#  published set, which is the only thing that works from both places.
PUBLISHED = {
 'getting-started.html':   'https://claude.ai/artifact/V9ZKEK5fTN6eSfwsXUwbhX',
 'programmers-guide.html': 'https://claude.ai/artifact/4aSEmtQNKFZ69p6ZrBKFmt',
 'template-guide.html':    'https://claude.ai/artifact/GNowfmcedV2PeR2qqoVWAp',
 'reference.html':         'https://claude.ai/artifact/KKSUT9nrRMcaNbsr1qfD1s',
}

def href(target, current):
    #  never link a volume to itself
    return '#' if target == current else PUBLISHED.get(target, target)

CSS = """
:root{
  --paper:#fbfcfd; --surface:#f1f5f9; --sunken:#e9eff5; --rule:#d6e0ea;
  --ink:#0f1720; --soft:#4e5f70; --faint:#7d8ea0;
  --accent:#2f6a9a; --accent-bg:#e4eef6; --accent-rule:#b9d3e6;
  --clarion:#166f69; --clarion-bg:#e2f1ef;
  --warn:#8a5a12; --warn-bg:#f7eeda;
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --paper:#0d131a; --surface:#151d26; --sunken:#111922; --rule:#25313d;
    --ink:#e2eaf2; --soft:#9aabbc; --faint:#6f8092;
    --accent:#6fadde; --accent-bg:#152738; --accent-rule:#28455f;
    --clarion:#4fb5ab; --clarion-bg:#102a29;
    --warn:#d8a545; --warn-bg:#2b2413;
  }
}
:root[data-theme="dark"]{
  --paper:#0d131a; --surface:#151d26; --sunken:#111922; --rule:#25313d;
  --ink:#e2eaf2; --soft:#9aabbc; --faint:#6f8092;
  --accent:#6fadde; --accent-bg:#152738; --accent-rule:#28455f;
  --clarion:#4fb5ab; --clarion-bg:#102a29;
  --warn:#d8a545; --warn-bg:#2b2413;
}
*{box-sizing:border-box}
body{margin:0; background:var(--paper); color:var(--ink);
  font-family:"IBM Plex Serif",Georgia,serif; font-size:16px; line-height:1.62;
  -webkit-font-smoothing:antialiased}
h1,h2,h3,h4,.ui{font-family:"IBM Plex Sans",system-ui,-apple-system,Segoe UI,sans-serif}
code,pre,.mono{font-family:"IBM Plex Mono",ui-monospace,Consolas,monospace}
a{color:var(--accent)}
.wrap{display:grid; grid-template-columns:270px minmax(0,1fr); align-items:start}
.side{position:sticky; top:0; height:100vh; overflow-y:auto; padding:24px 20px 60px;
  border-right:1px solid var(--rule); background:var(--surface)}
.brand{font-family:"IBM Plex Sans",sans-serif; font-weight:600; font-size:15px; margin:0 0 14px}
.brand b{color:var(--accent)}
/* ---- the four volumes ---- */
.vols{list-style:none; margin:0 0 18px; padding:0; display:flex; flex-direction:column; gap:3px;
  border-bottom:1px solid var(--rule); padding-bottom:16px}
.vols a{display:block; padding:7px 10px; border-radius:6px; text-decoration:none;
  font:500 13px/1.35 "IBM Plex Sans",sans-serif; color:var(--soft); border:1px solid transparent}
.vols a:hover{background:var(--sunken); color:var(--ink)}
.vols a.here{background:var(--accent-bg); border-color:var(--accent-rule); color:var(--accent)}
.vols small{display:block; font:400 11px/1.35 "IBM Plex Sans",sans-serif; color:var(--faint);
  margin-top:2px}
.vols a.here small{color:var(--accent)}
.filter{width:100%; margin:0 0 16px; padding:7px 10px; font:13px/1.4 "IBM Plex Sans",sans-serif;
  color:var(--ink); background:var(--paper); border:1px solid var(--rule); border-radius:6px}
.filter:focus{outline:2px solid var(--accent); outline-offset:1px}
.nav__g{font:600 10.5px/1 "IBM Plex Sans",sans-serif; letter-spacing:.11em; text-transform:uppercase;
  color:var(--faint); margin:18px 0 8px}
.nav__l{list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:1px}
.nav__l a{display:block; padding:4px 8px; border-radius:5px; text-decoration:none; color:var(--soft);
  font:400 13.5px/1.45 "IBM Plex Sans",sans-serif}
.nav__l a:hover{background:var(--sunken); color:var(--ink)}
.nav__l a.on{background:var(--accent-bg); color:var(--accent); font-weight:500}
.main{padding:0 0 120px; min-width:0}
.inner{max-width:980px; padding:0 40px}
.hero{padding:52px 40px 30px; border-bottom:1px solid var(--rule);
  background:linear-gradient(180deg,var(--accent-bg),transparent)}
.hero .inner{padding:0}
.eyebrow{font:600 11px/1 "IBM Plex Sans",sans-serif; letter-spacing:.14em; text-transform:uppercase;
  color:var(--accent); margin:0 0 12px}
h1{font-size:37px; line-height:1.1; margin:0 0 10px; letter-spacing:-.015em; text-wrap:balance}
.sub{font-size:17px; color:var(--soft); margin:0 0 18px; max-width:62ch}
.chips{display:flex; flex-wrap:wrap; gap:8px}
.chip{font:500 11.5px/1 "IBM Plex Sans",sans-serif; padding:6px 10px; border-radius:99px;
  border:1px solid var(--rule); background:var(--paper); color:var(--soft)}
.chip b{color:var(--ink); font-weight:600}
h2{font-size:26px; margin:60px 0 6px; letter-spacing:-.01em; scroll-margin-top:18px; text-wrap:balance}
h2 .k{font:600 10.5px/1 "IBM Plex Sans",sans-serif; letter-spacing:.12em; text-transform:uppercase;
  color:var(--accent); display:block; margin-bottom:9px}
h3{font-size:17.5px; margin:36px 0 10px; scroll-margin-top:18px}
h4{font-size:14.5px; margin:24px 0 6px; color:var(--soft); font-weight:600}
p{margin:0 0 14px; max-width:70ch}
.lead{color:var(--soft); max-width:70ch}
ul.b,ol.b{max-width:70ch; padding-left:20px; margin:0 0 16px}
ul.b li,ol.b li{margin:0 0 7px}
.code{background:var(--sunken); border:1px solid var(--rule); border-left:3px solid var(--accent-rule);
  border-radius:0 7px 7px 0; padding:14px 16px; overflow-x:auto; margin:0 0 18px;
  font-size:12.9px; line-height:1.62; position:relative}
.code code{white-space:pre; color:var(--ink)}
.code::after{content:attr(data-lang); position:absolute; top:0; right:0; padding:3px 9px;
  font:500 9.5px/1 "IBM Plex Sans",sans-serif; letter-spacing:.1em; text-transform:uppercase;
  color:var(--faint); background:var(--surface); border-left:1px solid var(--rule);
  border-bottom:1px solid var(--rule); border-radius:0 0 0 6px}
.code--use{margin:7px 0 2px; border-left-color:var(--clarion); background:var(--paper);
  font-size:12.4px; padding:9px 12px}
.code--use::after{content:'Clarion'; color:var(--clarion)}
p code,li code,td code{background:var(--sunken); border:1px solid var(--rule); border-radius:4px;
  padding:.06em .34em; font-size:.86em}
.tw{overflow-x:auto; margin:0 0 20px; border:1px solid var(--rule); border-radius:8px;
  background:var(--paper)}
table{border-collapse:collapse; width:100%; font-size:13.5px;
  font-family:"IBM Plex Sans",sans-serif}
th{text-align:left; font-weight:600; font-size:11px; letter-spacing:.08em; text-transform:uppercase;
  color:var(--faint); padding:9px 14px; border-bottom:1px solid var(--rule); background:var(--surface)}
td{padding:10px 14px; border-bottom:1px solid var(--rule); vertical-align:top}
tr:last-child td{border-bottom:0}
.fns .fn__n{width:210px; white-space:nowrap}
.fns .fn__n code{font-size:12.6px; color:var(--accent); font-weight:500; background:none;
  border:0; padding:0}
.fns .fn__s code{font-size:12.4px; color:var(--soft); background:none; border:0; padding:0;
  white-space:pre-wrap}
.fn__d{margin:5px 0 0; font-family:"IBM Plex Serif",serif; font-size:13.5px; color:var(--ink);
  max-width:74ch}
.ord{margin-left:7px; font:500 10px/1 "IBM Plex Mono",monospace; color:var(--faint);
  border:1px solid var(--rule); border-radius:4px; padding:2px 4px; vertical-align:1px}
.eq td:first-child code{color:var(--accent); background:none; border:0; padding:0}
.eq .v{font-variant-numeric:tabular-nums; color:var(--soft)}
.note{border:1px solid var(--rule); border-left:3px solid var(--accent); background:var(--surface);
  border-radius:0 7px 7px 0; padding:13px 16px; margin:0 0 18px; max-width:74ch}
.note--warn{border-left-color:var(--warn); background:var(--warn-bg)}
.note--cla{border-left-color:var(--clarion); background:var(--clarion-bg)}
.note__t{font:600 12px/1.3 "IBM Plex Sans",sans-serif; letter-spacing:.03em; margin:0 0 5px;
  text-transform:uppercase; color:var(--soft)}
.note--warn .note__t{color:var(--warn)} .note--cla .note__t{color:var(--clarion)}
.note__b p{margin:0 0 8px; font-size:14.5px} .note__b p:last-child{margin:0}
.stack{display:flex; flex-direction:column; gap:9px; margin:0 0 22px; max-width:640px}
.layer{border:1px solid var(--rule); border-radius:8px; padding:12px 15px; background:var(--surface);
  display:grid; grid-template-columns:118px 1fr; gap:14px; align-items:baseline}
.layer b{font:600 11px/1.4 "IBM Plex Sans",sans-serif; letter-spacing:.06em; text-transform:uppercase;
  color:var(--accent)}
.layer.cla b{color:var(--clarion)}
.layer p{margin:0; font-size:14px; color:var(--soft); max-width:none}
.arrow{text-align:center; color:var(--faint); font-size:12px; margin:-4px 0}
/* ---- where to next ---- */
.next{display:grid; grid-template-columns:repeat(auto-fit,minmax(210px,1fr)); gap:12px;
  margin:26px 0 0}
.next a{display:block; padding:14px 16px; border:1px solid var(--rule); border-radius:9px;
  background:var(--surface); text-decoration:none}
.next a:hover{border-color:var(--accent-rule); background:var(--accent-bg)}
.next b{display:block; font:600 14px/1.3 "IBM Plex Sans",sans-serif; color:var(--accent);
  margin-bottom:3px}
.next span{font:400 13px/1.45 "IBM Plex Serif",serif; color:var(--soft)}
.hide{display:none !important}
footer{margin-top:70px; padding:22px 40px 0; border-top:1px solid var(--rule); color:var(--faint);
  font:400 13px/1.6 "IBM Plex Sans",sans-serif}
@media (max-width:900px){
  .wrap{grid-template-columns:1fr}
  .side{position:static; height:auto; border-right:0; border-bottom:1px solid var(--rule)}
  .inner,.hero{padding-left:22px; padding-right:22px}
}
@media (prefers-reduced-motion:reduce){*{animation:none !important; transition:none !important}}
"""

JS = """
const q = document.getElementById('filter');
if (q) {
  const rows = [...document.querySelectorAll('tr.fn')];
  q.addEventListener('input', () => {
    const t = q.value.trim().toLowerCase();
    rows.forEach(r => r.classList.toggle('hide', t && !r.dataset.k.includes(t)));
    document.querySelectorAll('.tw').forEach(w => {
      const body = w.querySelector('tbody');
      if (!body) return;
      const any = [...body.querySelectorAll('tr')].some(r => !r.classList.contains('hide'));
      const h = w.previousElementSibling;
      w.classList.toggle('hide', !any);
      if (h && h.tagName === 'H3') h.classList.toggle('hide', !any);
    });
  });
}
/*  Which sidebar entry is lit.  An IntersectionObserver was the wrong
    instrument: one click crosses several headings at once, every one of them
    arrives in a single callback, and the last entry processed won - so the
    highlight settled one or two sections past the one that was clicked, and
    the page looked as though it had jumped there.  Position is the question,
    so ask position.  */
const links = [...document.querySelectorAll('.nav__l a')];
if (links.length) {
  const byId  = new Map(links.map(a => [a.getAttribute('href').slice(1), a]));
  const marks = [...document.querySelectorAll('h2[id],h3[id]')].filter(h => byId.has(h.id));
  const light = a => links.forEach(l => l.classList.toggle('on', l === a));
  let held = null, holdUntil = 0, queued = false;

  function spy() {
    queued = false;
    if (held) { light(held); return; }
    let cur = marks[0];
    for (const h of marks) {
      if (h.getBoundingClientRect().top <= 120) cur = h; else break;
    }
    //  the foot of the page belongs to the last section, however short it is
    if (innerHeight + scrollY >= document.documentElement.scrollHeight - 2)
      cur = marks[marks.length - 1];
    if (cur) light(byId.get(cur.id));
  }

  //  a click owns the highlight until the scroll it started has landed
  links.forEach(a => a.addEventListener('click', () => {
    held = a; holdUntil = performance.now() + 700; light(a);
  }));
  const later = () => { if (!queued) { queued = true; requestAnimationFrame(spy); } };
  addEventListener('scroll', () => {
    if (held && performance.now() > holdUntil) held = null;
    later();
  }, {passive: true});
  addEventListener('resize', later);
  if (marks.length) spy();
}
"""

PROBLEMS = []

def volnav(current):
    out = ['<ul class="vols">']
    for i, (hrefname, name, blurb) in enumerate(VOLUMES):
        here = ' class="here"' if hrefname == current else ''
        out.append('<li><a href="%s"%s>%s. %s<small>%s</small></a></li>'
                   % (href(hrefname, current), here, i + 1, esc(name), esc(blurb)))
    out.append('</ul>')
    return ''.join(out)

def headings(body):
    """Every anchored id in the body, with the words actually printed above it."""
    out = {}
    for m in re.finditer(r'<h([23]) id="([^"]+)"[^>]*>(.*?)</h\1>', body, re.S):
        txt = re.sub(r'<span class="k">.*?</span>', '', m.group(3), flags=re.S)
        out[m.group(2)] = re.sub(r"\s+", ' ', re.sub(r'<[^>]+>', '', txt)).strip()
    return out

def secnav(groups, titles):
    #  The sidebar prints the heading itself, never a second wording of it.
    #  Two hand-kept lists drift, and a reader who clicks "The event pump" and
    #  lands under a heading worded differently believes the link is broken.
    out = []
    for group, items in groups:
        if group: out.append('<p class="nav__g">%s</p>' % esc(group))
        out.append('<ul class="nav__l">')
        for aid, label in items:
            out.append('<li><a href="#%s">%s</a></li>' % (aid, esc(titles.get(aid, label))))
        out.append('</ul>')
    return ''.join(out)

def nextcards(names):
    cards = []
    for h in names:
        for hrefname, name, blurb in VOLUMES:
            if hrefname == h:
                cards.append('<a href="%s"><b>%s &rarr;</b><span>%s</span></a>'
                             % (PUBLISHED.get(hrefname, hrefname), esc(name), esc(blurb)))
    return '<div class="next">%s</div>' % ''.join(cards)

def page(filename, title, eyebrow, heading, sub, chips, groups, body, showfilter=False):
    titles = headings(body)
    linked = [aid for _, items in groups for aid, _ in items]
    for aid in linked:
        if aid not in titles:
            PROBLEMS.append('%s: the nav points at #%s, which is not a heading' % (filename, aid))
    for aid in titles:
        if aid not in linked:
            PROBLEMS.append('%s: heading #%s (%s) is in no nav' % (filename, aid, titles[aid]))
    nav = volnav(filename) + \
          ('<label class="ui" style="font-size:11px;color:var(--faint);letter-spacing:.08em;'
           'text-transform:uppercase" for="filter">Filter</label>'
           '<input id="filter" class="filter" type="search" placeholder="Import, SheetName&hellip;" '
           'autocomplete="off">' if showfilter else '') + secnav(groups, titles)
    chiphtml = ''.join('<span class="chip">%s</span>' % c for c in chips)
    doc = ('<title>%s</title>\n'
           '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
           '<link rel="preconnect" href="https://fonts.googleapis.com">\n'
           '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n'
           '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?'
           'family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&'
           'family=IBM+Plex+Serif:wght@400;600&display=swap">\n'
           '<style>%s</style>\n'
           '<div class="wrap">\n<nav class="side">\n'
           '  <p class="brand"><b>MyImportExport</b></p>\n%s\n</nav>\n'
           '<main class="main">\n'
           '  <header class="hero"><div class="inner">\n'
           '    <p class="eyebrow">%s</p>\n    <h1>%s</h1>\n    <p class="sub">%s</p>\n'
           '    <div class="chips">%s</div>\n'
           '  </div></header>\n  <div class="inner">%s\n'
           '    <footer>MyImportExport &mdash; four volumes. The reference is generated from '
           '<code>MyImportExport.inc</code>, <code>MyImportExport.tpl</code> / <code>.tpw</code> and the helper&rsquo;s '
           '<code>Program.cs</code>, so what it lists is what is in the build.</footer>\n'
           '  </div>\n</main>\n</div>\n<script>%s</script>\n'
           % (esc(title), CSS, nav, esc(eyebrow), esc(heading), sub, chiphtml, body, JS))
    io.open('docs/' + filename, 'w', encoding='utf-8', newline='\n').write(doc)
    return len(doc)

# =====================================================================
#  1  GETTING STARTED
# =====================================================================
S_HAND = """
  PROGRAM

  INCLUDE('MyImportExport.inc'),ONCE

  MAP
  END

Customer   FILE,DRIVER('TOPSPEED'),NAME('customer.tps'),PRE(CUS),CREATE,THREAD
KeyId        KEY(CUS:Id),PRIMARY,NOCASE
Record       RECORD
Id             LONG
Name           STRING(40)
Since          DATE
Balance        DECIMAL(11,2)
             END
           END

MIE        MyImportExportClass

  CODE
  MIE.Init()
  MIE.SetTable(Customer, 'Customer', CUS:KeyId)
  MIE.AddField('CUS:Id',      'Id',      'LONG',    '@n_10',   CUS:Id, 1)
  MIE.AddField('CUS:Name',    'Name',    'STRING',  '@s40',    CUS:Name)
  MIE.AddField('CUS:Since',   'Since',   'DATE',    '@d17',    CUS:Since)
  MIE.AddField('CUS:Balance', 'Balance', 'DECIMAL', '@n-14.2', CUS:Balance)
  MIE.LoadMap()                    ! what was used last time, if anything
  MIE.Ask()                        ! the import / export window
  MIE.Kill()
"""

S_HAND_PRJ = """
_MIEDllMode_=>0;_MIELinkMode_=>1          ! Project > Properties > Compiler > Defines
"""

def build_getting_started():
    B = []
    add = B.append
    add('<h2 id="what"><span class="k">Overview</span>What it does</h2>')
    add('''<p>MyImportExport lets the users of a Clarion program move the data of any table in the
dictionary in and out of <b>CSV, TSV, JSON, XML, XLSX and XLS</b> files. One window does both
directions. The user picks a file, an Excel sheet if there is one, ticks the columns to use and lines
each column of the file up with a field of the table. The settings are remembered per table, so the
next run of the same job is two clicks.</p>''')
    add('''<div class="stack">
<div class="layer"><b>Template</b><p>Writes a procedure <code>MIE_ImportExport(table, mode)</code> that knows
every table and field in your dictionary, and drops Import / Export buttons on your browses.</p></div>
<div class="arrow">&darr;</div>
<div class="layer cla"><b>Clarion class</b><p><code>MyImportExportClass</code>: the window, the mapping, the
import modes, the type conversion, and the reads and writes on your table.</p></div>
<div class="arrow">&darr;</div>
<div class="layer"><b>Helper</b><p><code>MIEConvert.exe</code>: reads and writes the six formats. A single
110 KB program; Excel does not need to be installed.</p></div>
</div>''')
    add('<h2 id="needs"><span class="k">Before you start</span>Requirements</h2>')
    add(table(['What', 'Needed'], [
        ['Clarion', '12 (ABC or Clarion/Legacy template chain)'],
        ['File driver', 'DOS must be registered &mdash; the class uses it for its temporary files. It is, in a standard install.'],
        ['On the users\' PCs', '.NET Framework 4.8 for <code>MIEConvert.exe</code>. Windows 10 and 11 ship with it.'],
        ['Excel', 'Not needed. The helper writes real .xlsx and .xls files itself.'],
    ]))
    add('<h2 id="install"><span class="k">Step 1</span>Install</h2>')
    add('<p>From the repository folder run the install script. It copies the files into your Clarion '
        'installation and registers the template.</p>')
    add(code('pwsh .\\install.ps1                      # or: pwsh .\\install.ps1 -ClarionRoot D:\\clarion12', 'shell'))
    add(table(['File', 'Goes to'], [
        ['<code>template\\win\\MyImportExport.tpl</code>, <code>.tpw</code>', '<code>accessory\\template\\win</code>'],
        ['<code>libsrc\\win\\MyImportExport.inc</code>, <code>.clw</code>', '<code>accessory\\libsrc\\win</code>'],
        ['<code>bin\\MIEConvert.exe</code>', '<code>accessory\\bin</code>'],
    ]))
    add(note('cla', 'Restart the IDE', '<p>The template registry is read when the IDE starts. If Clarion was '
        'open while you installed, close and reopen it before you look for the templates.</p>'))
    add('<h2 id="app"><span class="k">Step 2</span>Add it to an app</h2>')
    add('''<ol class="b">
<li>Open the app, <b>Global</b> &rarr; <b>Extensions</b> &rarr; <b>Insert</b> &rarr;
<code>MyImportExportGlobal</code>. The defaults are right for a single-EXE app.</li>
<li>Open a browse procedure, <b>Window</b> designer &rarr; <b>Control Templates</b> &rarr;
<code>MyImportExportButtons</code>. Place the two buttons where you want them.</li>
<li>Generate and run. Click <b>Export...</b> on the browse.</li>
</ol>''')
    add('''<p>The buttons work on the browse's table. The global extension made the procedure behind them,
<code>MIE_ImportExport</code>, which you can also call from anywhere yourself:</p>''')
    add(code("MIE_ImportExport('Customer', MIE:Mode:Export)   ! straight to export\n"
             "MIE_ImportExport('')                            ! the user picks a table first"))
    add('<h2 id="first-export"><span class="k">Step 3</span>Your first export</h2>')
    add('''<ol class="b">
<li><b>Action</b> is already <i>Export</i>. Pick a <b>Format</b> &mdash; XLSX is the default.</li>
<li>Click <b>...</b> next to <b>File</b> and choose where to save. The extension follows the format.</li>
<li>For Excel, type a <b>Sheet</b> name, or leave it blank for <i>Sheet1</i>.</li>
<li>In the field list, untick what you do not want (double-click or Space). Change a <b>Column header</b>
in the box below the list, and reorder with <b>Move Up</b> / <b>Move Down</b>.</li>
<li>Click <b>Export</b>. A message tells you how many records went out.</li>
</ol>''')
    add('<p>Dates come out as real Excel dates, numbers as numbers, and the header row is bold.</p>')
    add('<h2 id="first-import"><span class="k">Step 4</span>Your first import</h2>')
    add('''<ol class="b">
<li>Switch <b>Action</b> to <i>Import</i> and choose the file. The sheets and columns are read at once.</li>
<li>Pick the <b>Sheet</b>. Columns whose names match a field are mapped already; the <b>Sample</b> column
shows a value from the first row so you can see what you are mapping.</li>
<li>For a field that did not match, select it and choose its <b>Source column</b> below the list.</li>
<li>Choose the <b>Import mode</b>: add new records, add or update by primary key, update only, or replace
all records.</li>
<li>Click <b>Import</b>. The result shows rows read, added, updated, skipped and failed.</li>
</ol>''')
    add('<h3 id="first-multi">Several tables at once</h3>')
    add('''<p>Tick <b>Show the "Export tables..." button</b> on the buttons control template, or call
<code>MIE_ExportTables()</code>. Tick the tables, choose XLSX and a file, and click <b>Export</b>: each table
becomes a sheet named after it. JSON gives one collection per table and XML one element per table; CSV and
TSV write one file per table.</p>''')
    add(note('warn', 'Replace all deletes first', '<p><i>Replace all records</i> empties the table before it '
        'adds the rows, and asks first. Use it for lookup tables you reload from a master file.</p>'))
    add('<h2 id="hand"><span class="k">Without the template</span>The smallest program by hand</h2>')
    add('<p>The class works on its own. Name the table, offer its fields, open the window:</p>')
    add(code(S_HAND))
    add('<p>Set the two project defines so the class is compiled into the program, and add the DOS driver '
        'to the project:</p>')
    add(code(S_HAND_PRJ))
    add('<h2 id="ship"><span class="k">Deploying</span>Shipping your program</h2>')
    add('''<ul class="b">
<li>Put <code>MIEConvert.exe</code> next to your program's exe. The global extension can copy it to the
output folder on every build (<b>Helper &amp; INI</b> tab).</li>
<li>Saved mappings go to your program's INI file (ABC: <code>INIMgr.FileName</code>), in one
<code>[MIE_&lt;table&gt;]</code> section per table.</li>
<li>Nothing is registered and nothing is installed: the helper is a plain exe.</li>
</ul>''')
    add('<h2 id="demos"><span class="k">Examples</span>The demos</h2>')
    add(table(['Folder', 'What is in it'], [
        ['<code>example\\</code>', '<code>MIEDemo.dctx</code> (Customer with auto-increment key, dates, times, an array, a MEMO and an excluded field; Product; an excluded AppLog table) and <code>MIEDemo.txa</code>, an ABC app with the buttons on a browse. Import the dictionary, then the TXA.'],
        ['<code>test\\</code>', '<code>MIETest.clw</code> exports a table to all six formats, imports each file into a copy and compares every field. <code>pwsh test\\build.ps1</code> builds and runs it.'],
        ['<code>helper\\tests\\</code>', '<code>run_tests.py</code> checks the helper alone: round trips, files from Excel and other tools, every option.'],
    ]))
    add('<h2 id="next1"><span class="k">Getting Started</span>Where to go next</h2>')
    add(nextcards(['programmers-guide.html', 'template-guide.html', 'reference.html']))
    nav = [('Start here', [('what', ''), ('needs', ''), ('install', ''), ('app', ''),
                           ('first-export', ''), ('first-import', ''), ('first-multi', '')]),
           ('More', [('hand', ''), ('ship', ''), ('demos', ''), ('next1', '')])]
    return page('getting-started.html', 'MyImportExport Getting Started', 'Volume 1', 'Getting Started',
                'Install the template, put Import and Export buttons on a browse, and move your first table '
                'in and out of Excel.',
                ['<b>6</b> file formats', '<b>3</b> templates', '<b>1</b> helper exe', TPLVER.split(' - ')[-1]],
                nav, ''.join(B))


# =====================================================================
#  2  PROGRAMMER'S GUIDE
# =====================================================================
S_HEADLESS = """
MIE        MyImportExportClass
  CODE
  MIE.Init()
  MIE.Silent  = 1                         ! no message boxes
  MIE.IniFile = ''                        ! do not touch the INI
  MIE.SetTable(Customer, 'Customer', CUS:KeyId)
  MIE.AddField('CUS:Id',   'Id',   'LONG',   '@n_10', CUS:Id, 1)
  MIE.AddField('CUS:Name', 'Name', 'STRING', '@s40',  CUS:Name)

  ! nightly export
  MIE.Format    = 'XLSX'
  MIE.FileName  = 'c:\\exchange\\customers.xlsx'
  MIE.SheetName = 'Customers'
  IF MIE.Export() THEN Log('export: ' & MIE.ErrorText).

  ! morning import of the changes
  MIE.Format     = 'CSV'
  MIE.FileName   = 'c:\\exchange\\changes.csv'
  MIE.ImportMode = MIE:Import:Upsert
  MIE.LoadColumns()                       ! read the header row ...
  MIE.AutoMap()                           ! ... and map it by name
  IF MIE.Import()
    Log('import: ' & MIE.ErrorText)
  ELSE
    Log(MIE.ResultText())
  END
  MIE.Kill()
"""

S_DERIVE = """
MIE        CLASS(MyImportExportClass)
ValidateRecord PROCEDURE(),BYTE,DERIVED
InsertRecord   PROCEDURE(),BYTE,DERIVED
           END

MIE.ValidateRecord PROCEDURE()
  CODE
  IF CUS:Email = '' THEN RETURN 1.        ! skip the row
  CUS:Email = LOWER(CUS:Email)            ! clean it up on the way in
  RETURN 0

MIE.InsertRecord PROCEDURE()
  CODE
  CUS:CreatedOn = TODAY()
  RETURN PARENT.InsertRecord()
"""

S_TSV = """Id\tName\tSince\tAlarm\tBalance
N\tS\tD\tT\tN
1\tSmith, John\t2020-01-02\t08:30:15\t1234.56
2\tSay "Hi" \\ttab\\\\back\t\t\t-42.5
3\tLine1\\r\\nLine2\t2024-02-29\t23:59:59\t0"""

S_INI = """[MIE_Customer]
Mode=2
Format=XLSX
FileName=C:\\exchange\\customers.xlsx
SheetName=Customers
HasHeader=1
ImportMode=2
F_CUS:Id=1|1|Id|Customer No
F_CUS:Name=1|2|Name|Customer name
F_CUS:Since=0|3|Since|"""

def build_programmers_guide():
    B = []
    add = B.append
    add('<h2 id="parts"><span class="k">Concepts</span>How the parts fit</h2>')
    add('''<p>The class never reads an Excel or JSON file itself. Every run goes through one plain text
file in the Windows temp folder, and <code>MIEConvert.exe</code> turns that file into the real format
or back. The class only knows how to read and write that one text file, and the helper only knows
files &mdash; neither knows about the other's job.</p>''')
    add(table(['Step', 'Export', 'Import'], [
        ['1', 'The class walks the table (in primary key order) and writes the selected fields to a temp file.',
              'The class runs <code>MIEConvert import</code>, which writes the source file as a temp file.'],
        ['2', 'It runs <code>MIEConvert export</code>, which writes the CSV, JSON, XML or Excel file.',
              'The class reads the temp file row by row, fills the record buffer and inserts or updates.'],
        ['3', 'The temp file is deleted.', 'The temp file is deleted.'],
    ]))
    add('<h3 id="tsv">The intermediate file</h3>')
    add('''<p>Tab separated, one record per line, CRLF line ends, Windows ANSI. Inside a value only four
characters are escaped: <code>\\\\</code>, <code>\\t</code>, <code>\\r</code> and <code>\\n</code>. The first
line holds the column names. On export a second line holds one type code per column &mdash;
<code>S</code> string, <code>N</code> number, <code>D</code> date, <code>T</code> time &mdash; so the helper
can write real Excel number, date and time cells.</p>''')
    add(code(S_TSV, 'tsv'))
    add('<h2 id="fields"><span class="k">Concepts</span>Fields and columns</h2>')
    add('''<p>Each <code>AddField</code> call adds one row to the <code>Fields</code> queue: the field's label,
its default column name, its dictionary type and picture, and an <code>ANY</code> reference to the field
itself. Everything the window shows and everything Export and Import do is driven by that queue.</p>''')
    add(table(['Queue field', 'Used for'], [
        ['<code>Selected</code>', 'Export: the column is written. Import: the field is filled.'],
        ['<code>Order</code>', 'Export column order. Move Up / Down swaps it; the queue is kept sorted on it.'],
        ['<code>Header</code>', 'Export: the column name written. Starts as the field\'s name.'],
        ['<code>SourceName</code>', 'Import: the name of the source column mapped to this field.'],
        ['<code>SourceCol</code>', 'Import: that column\'s position in the current file, worked out again by <code>ResolveMap</code> on every run.'],
        ['<code>IsKey</code>', 'Part of the primary key: Add-or-update and Update-only find records through it.'],
    ]))
    add('<p>Mapping is kept by <b>name</b>, not by position, so a file whose columns come in a different '
        'order next month still imports correctly.</p>')
    add('<h3 id="automap">Auto Map</h3>')
    add('''<p>Auto Map compares names after removing the prefix (<code>CUS:</code>), case, spaces,
underscores, dashes, dots and brackets. <code>Cust Number</code>, <code>CUST_NUMBER</code> and
<code>CUS:CustNumber</code> all match. A field matches on its name, its label or its current header.
When the file has no header row, the columns are called <code>Column1</code>, <code>Column2</code> ... and
Auto Map pairs them with the fields by position.</p>''')
    add('<h2 id="modes"><span class="k">Concepts</span>Import modes</h2>')
    add(table(['Mode', 'Equate', 'What happens to each row'], [
        ['Add new records', '<code>MIE:Import:Add</code>', 'Inserted. A duplicate key is counted as failed.'],
        ['Add or update', '<code>MIE:Import:Upsert</code>', 'The primary key from the row is looked up. Found: the mapped fields are written over the record and it is updated &mdash; unmapped fields keep their values. Not found: inserted.'],
        ['Update existing only', '<code>MIE:Import:Update</code>', 'As above, but a row with no matching record is skipped.'],
        ['Replace all records', '<code>MIE:Import:Replace</code>', 'Every record of the table is deleted first, then each row is inserted.'],
    ]))
    add('''<p>The two update modes need the primary key: the table must have one, and its fields must be
mapped. When no key field is mapped, new records are <i>primed</i> &mdash; under ABC that gives them the
next auto-increment number. When the key <i>is</i> mapped, the imported key values are kept.</p>''')
    add('<h2 id="values"><span class="k">Concepts</span>Dates, times and numbers</h2>')
    add(table(['Field', 'Exported as', 'Imported from'], [
        ['<code>DATE</code>, or a number with an <code>@D</code> picture', '<code>yyyy-mm-dd</code>; an Excel date cell', '<code>yyyy-mm-dd</code> (also with <code>/</code> or <code>.</code>, and with a time after it), <code>yyyymmdd</code>, a Clarion date number, or text in the field\'s own picture'],
        ['<code>TIME</code>, or a number with an <code>@T</code> picture', '<code>hh:mm:ss</code>; an Excel time cell', '<code>hh:mm[:ss]</code>, a date-time (the time part is used), a Clarion time number, or the picture'],
        ['Numbers', 'Plain, with a <code>.</code> decimal point; an Excel number', 'Any number; <code>true/yes/y</code> = 1, <code>false/no/n</code> = 0; otherwise the digits are picked out'],
        ['Strings', 'As stored, trailing spaces removed', 'As is'],
    ]))
    add('<p>Zero dates and times export as empty cells and import back as zero. With <b>Format with dictionary '
        'pictures</b> (<code>UsePictures</code>) dates, times and numbers are written exactly as your program '
        'shows them, as text.</p>')
    add('<h2 id="formats"><span class="k">Formats</span>What each format does</h2>')
    add(table(['Format', 'Import', 'Export'], [
        ['CSV', 'Quoted fields, doubled quotes, line breaks inside quotes. Delimiter of your choice. Encoding detected (BOM, UTF-8, else ANSI).', 'Quotes only where needed. UTF-8 with BOM, so Excel shows accents correctly.'],
        ['TSV', 'As CSV with a tab.', 'As CSV with a tab.'],
        ['JSON', 'An array of objects: the columns are every key seen, in first-seen order. Nested objects become <code>parent.child</code>; arrays become JSON text. <code>true</code>/<code>false</code> become 1/0.', 'An array of objects; numbers unquoted, empty numbers null. Optionally wrapped: <code>{"name":[...]}</code>.'],
        ['XML', 'The repeating row element is found automatically, or named. Columns are the attributes and child elements.', '<code>&lt;Data&gt;&lt;Row&gt;&lt;Name&gt;...</code>, names of your choice. Invalid characters in names become <code>_</code>.'],
        ['XLSX', 'Any sheet. Shared and inline strings, dates, booleans, cached formula values, sparse rows.', 'Real number, date and time cells, bold header. Can add or replace one sheet in an existing workbook.'],
        ['XLS', 'Excel 97&ndash;2003 workbooks, any sheet.', 'A real BIFF8 workbook. Up to 65,536 rows and 256 columns.'],
    ]))
    add('<h3 id="excel">Excel sheets</h3>')
    add('''<p>On import, <code>LoadSheets</code> lists the sheets and <code>SheetName</code> picks one (blank =
the first). Excel's first non-empty row is the header and completely empty rows are skipped. On export,
<code>SheetName</code> names the new sheet. With <code>ReplaceSheet</code> on an existing .xlsx, only that
sheet is added or replaced and every other sheet keeps its content and formatting &mdash; so one workbook can
collect several tables, one per sheet.</p>''')
    add('<h3 id="multi">Several tables in one file</h3>')
    add('''<p>Several tables can go into one file, each kept apart under its own name. Each table is written
with the columns, order and headers saved for it in the single-table window, so set those up once per
table and the multi-table export reuses them.</p>''')
    add(table(['Format', 'How the tables are kept apart'], [
        ['JSON', 'One collection per table: <code>{"Customer":[...], "Product":[...]}</code>. An empty table is <code>[]</code>.'],
        ['XML', 'One element per table inside the root: <code>&lt;Data&gt;&lt;Customer&gt;&lt;Row&gt;...&lt;/Row&gt;&lt;/Customer&gt;&lt;Product&gt;...&lt;/Data&gt;</code>.'],
        ['XLSX, XLS', 'One sheet per table, named after the table. Names are cleaned to Excel\'s rules (31 characters, no <code>: \\ / ? * [ ]</code>, unique), and an empty table gets a header-only sheet.'],
        ['CSV, TSV', 'These hold one table per file, so each table goes to its own file: <code>backup.csv</code> becomes <code>backup_Customer.csv</code>, <code>backup_Product.csv</code>.'],
    ]))
    add(code("MIE.AddTable('Customer') ; MIE.AddTable('Product')   ! the template does this for every table\n"
             "MIE.LoadTablesMap()                                ! last ticked tables, format and file\n"
             "MIE.AskTables()                                    ! or set Tables.Selected and call ExportTables()"))
    add('<p>Under the window, <code>ExportTables</code> calls <code>SetupTable</code>, <code>LoadMap</code> and '
        '<code>BatchAdd</code> for each ticked table, then <code>BatchFinish</code> runs the helper\'s '
        '<code>exportmulti</code> command once. You can drive the batch methods yourself to combine tables '
        'from different places.</p>')
    add('<h2 id="saved"><span class="k">How-to</span>Saved mappings</h2>')
    add('<p>After every successful run the window calls <code>SaveMap</code>, and the generated procedure calls '
        '<code>LoadMap</code> before it opens the window. Each field line holds '
        '<i>selected | order | header | source column</i>:</p>')
    add(code(S_INI, 'ini'))
    add('<h2 id="headless"><span class="k">How-to</span>Running without a window</h2>')
    add('<p>Everything the window does is a property and a method call, so scheduled jobs and services use the '
        'same class. Call <code>LoadColumns</code> and <code>AutoMap</code> (or <code>MapField</code>) before '
        '<code>Import</code>: the mapping is by name, and the class has to see the header first.</p>')
    add(code(S_HEADLESS))
    add('<h2 id="derive"><span class="k">How-to</span>Rules and custom table I/O</h2>')
    add('''<p>Every read and write on your table goes through a virtual method, so you change behaviour by
deriving. <code>ValidateRecord</code> runs after the row is in the record buffer and before it is written
&mdash; return non-zero to skip the row, or fix values on the way in. <code>ExportFilter</code> decides
record by record what is exported.</p>''')
    add(code(S_DERIVE))
    add('<p>The template does exactly this for you, routing the I/O through ABC\'s <code>Access:</code> and '
        '<code>Relate:</code> objects and giving you embed points in each method. See the Template Guide.</p>')
    add('<h2 id="results"><span class="k">How-to</span>Errors and results</h2>')
    add('''<p><code>Export</code>, <code>Import</code>, <code>LoadColumns</code> and <code>LoadSheets</code>
return 0 when they ran. Otherwise <code>ErrorText</code> says why &mdash; including the helper's own
message, such as a sheet that does not exist or an .xls that is too big. A run that worked can still have
refused rows: check <code>Failed</code> and <code>LastFailure</code>. <code>ResultText</code> puts it all in
one message.</p>''')
    add(table(['Counter', 'Export', 'Import'], [
        ['<code>Processed</code>', 'records written', 'data rows read'],
        ['<code>Added</code>', '&mdash;', 'records inserted'],
        ['<code>Updated</code>', '&mdash;', 'records updated'],
        ['<code>Skipped</code>', 'records ExportFilter left out', 'rows ValidateRecord refused, and Update-only rows with no match'],
        ['<code>Failed</code>', '&mdash;', 'inserts or updates that returned an error'],
    ]))
    add('<h2 id="notes"><span class="k">Clarion notes</span>Things the language does to you</h2>')
    add('<p>Behaviour that belongs to Clarion rather than to this library, found the hard way while building '
        'it. Each one cost real time; they are here so they do not cost it again.</p>')
    add('<h3 id="n-any">An ANY in a queue is shared</h3>')
    add('''<p>The field queue holds an <code>ANY</code> reference per field. Setting
<code>Q.Ref &amp;= NULL</code> before <code>CLEAR(Q)</code> to add the next entry changed the entries already
in the queue: every field ended up pointing at the last one added, and the first export wrote the same
value into every column. Do what ABC's <code>FieldPairsClass.AddPair</code> does &mdash; <code>CLEAR(Q)</code>,
then <code>&amp;=</code>, then <code>ADD</code> &mdash; and NULL the references only when tearing the queue
down.</p>''')
    add('<h3 id="n-slice">Zero-length slices</h3>')
    add('''<p><code>S[1 : 0]</code> is not a safe empty string. Wherever a line may be empty the class passes
one byte more than the line (<code>LineBuf[1 : LineLen + 1]</code>) and the callee subtracts it, and the
line buffer always keeps one spare byte so that slice stays inside it.</p>''')
    add('<h3 id="n-time">@T4 pads with a space</h3>')
    add('<p><code>FORMAT(t, @T4)</code> gives <code>&nbsp;8:30:15</code> with a leading space. ISO times need '
        '<code>@T04</code>, which zero-pads to <code>08:30:15</code>.</p>')
    add('<h3 id="n-run">RUN and RUNCODE</h3>')
    add('''<p><code>RUN(cmd, 1)</code> waits for the helper and <code>RUNCODE()</code> returns its exit code.
<code>RUN</code> starts the process directly &mdash; no command shell &mdash; so a <code>;</code> or
<code>|</code> in a quoted argument is passed through untouched, and the helper is built as a windowless exe
so nothing flashes on screen. Its error text comes back through a file
(<code>--errfile</code>), since there is no console to read.</p>''')
    add('<h3 id="n-dos">The class needs the DOS driver</h3>')
    add('<p>The temp file is read and written in 32 KB blocks through a <code>DRIVER(\'DOS\')</code> file. A '
        'project without the DOS driver fails at link time with <i>Unresolved External DOS</i>; the global '
        'extension adds the driver for you.</p>')
    add('<h3 id="n-ansi">The temp file is ANSI</h3>')
    add('<p>Clarion strings are single-byte, so the intermediate file uses the Windows ANSI code page. '
        'Characters the code page cannot hold arrive as <code>?</code>. The helper reads UTF-8 and UTF-16 '
        'sources fine; it is only the hand-over to Clarion that is limited.</p>')
    add('<h3 id="n-abc">ABC TryInsert renumbers</h3>')
    add('''<p>On a table with an auto-increment key, ABC's <code>TryInsert</code> always gives the record the
next number, throwing away an imported key. The generated hooks therefore insert with a plain
<code>ADD</code> when the key column is mapped, and through <code>TryInsert</code> (after
<code>PrimeRecord</code>) when it is not. Likewise <code>Relate:</code> deletes cascade through the
dictionary's relations; <i>Replace all</i> deletes through <code>Access:</code> unless you choose otherwise.</p>''')
    add('<h3 id="n-tpl">Template pitfalls</h3>')
    add('''<ul class="b">
<li><code>#IF</code> treats the string <code>'0'</code> as true. Compare explicitly, or keep flags numeric.</li>
<li>A <code>#GROUP</code> swallows everything after it, so all groups live in the .tpw, included at the very end of the .tpl.</li>
<li>The registry finds template files through the redirection file. Registering straight from a repository folder fails with <i>Could not open include file</i>; install into <code>accessory\\template\\win</code> first.</li>
<li><code>#?</code> lines are written in column 1 unless indented inside the line itself.</li>
</ul>''')
    add('<h2 id="next2"><span class="k">Programmer\'s Guide</span>Where to go next</h2>')
    add(nextcards(['template-guide.html', 'reference.html', 'getting-started.html']))
    nav = [('Concepts', [('parts', ''), ('tsv', ''), ('fields', ''), ('automap', ''), ('modes', ''),
                         ('values', '')]),
           ('Formats', [('formats', ''), ('excel', ''), ('multi', '')]),
           ('How-to', [('saved', ''), ('headless', ''), ('derive', ''), ('results', '')]),
           ('Clarion notes', [('notes', ''), ('n-any', ''), ('n-slice', ''), ('n-time', ''), ('n-run', ''),
                              ('n-dos', ''), ('n-ansi', ''), ('n-abc', ''), ('n-tpl', '')]),
           ('', [('next2', '')])]
    return page('programmers-guide.html', "MyImportExport Programmer's Guide", 'Volume 2', "Programmer's Guide",
                'How an import and an export actually run, what each format does, and how to bend the class to '
                'your own rules.',
                ['<b>4</b> import modes', '<b>6</b> formats', '<b>%d</b> virtual hooks'
                 % len([m for m in METHLIST if m['group'] == 'Virtual hooks'])],
                nav, ''.join(B))


# =====================================================================
#  3  TEMPLATE GUIDE
# =====================================================================
TAB_NOTES = {
 ('MyImportExportGlobal', 'General'): 'Turns the template on and off, and decides where MIE_ImportExport is generated.',
 ('MyImportExportGlobal', 'Helper & INI'): 'Where the helper and the saved mappings live at run time.',
 ('MyImportExportGlobal', 'Tables'): 'Which tables are offered, and how Replace all deletes.',
 ('MyImportExportGlobal', 'Multi-DLL'): 'Where the class code lives in a suite of DLLs. Default does the right thing in almost every app.',
}

S_GENPROC = """
MIE_DictClass        CLASS(MyImportExportClass),TYPE   ! one class, shared by both procedures
FM                     &FileManager
RM                     &RelationManager
Prepare                PROCEDURE                       ! helper path, INI, default format
SetupTable             PROCEDURE(STRING pName),BYTE,DERIVED
  ...                                                  ! the ABC hooks, see below
                     END

MIE_ImportExport     PROCEDURE(STRING pTable,BYTE pMode)
ThisMIE              MIE_DictClass
  CODE
  TableName = pTable
  IF TableName = '' THEN DO PickTable.                 ! small list of every offered table
  ThisMIE.Prepare()
  IF ThisMIE.SetupTable(TableName) <> 0 THEN ... RETURN 0.
  ThisMIE.LoadMap()
  Result = ThisMIE.Ask(pMode)
  ThisMIE.Kill()
  RETURN Result

MIE_ExportTables     PROCEDURE(<STRING pTables>)
ThisMIE              MIE_DictClass
  CODE
  ThisMIE.Prepare()
  ThisMIE.AddTable('Customer','Customers')             ! one per offered table
  ThisMIE.AddTable('Product','Products')
  ThisMIE.LoadTablesMap()                              ! then pTables, if given, sets the ticks
  Result = ThisMIE.AskTables()
  ThisMIE.Kill()
  RETURN Result

MIE_DictClass.SetupTable PROCEDURE(STRING pName)
  CODE
  CASE UPPER(pName)
  OF 'CUSTOMER'                                        ! Customers
    SELF.FM &= Access:Customer
    SELF.RM &= Relate:Customer
    SELF.SetTable(Customer,'Customer',CUS:KeyCustNumber)
    SELF.AddField('CUS:CustNumber','CustNumber','LONG','@n_10',CUS:CustNumber,1)
    SELF.AddField('CUS:Name','Name','STRING','@s40',CUS:Name,0)
    SELF.AddField('CUS:Phones[1]','Phones_1','STRING','@s20',CUS:Phones[1],0)
    ...
  OF 'PRODUCT'
    ...
  ELSE
    RETURN PARENT.SetupTable(pName)                    ! 1 = unknown table
  END
  RETURN 0
"""

def prompt_table(t, tab):
    rows = []
    for p in t['prompts']:
        if p['tab'] != tab: continue
        rows.append(['%s%s' % (esc(p['label'].rstrip(':')),
                               '<br><small style="color:var(--faint)">%s</small>' % esc(p['box']) if p['box'] else ''),
                     '<code>%s</code>' % esc(p['sym']), esc(p['type']),
                     '<code>%s</code>' % esc(p['default']) if p['default'] else '&mdash;'])
    return table(['Prompt', 'Symbol', 'Kind', 'Default'], rows)

def build_template_guide():
    B = []
    add = B.append
    byname = {t['name']: t for t in TEMPLATES}
    add('<h2 id="set"><span class="k">Overview</span>The template set</h2>')
    add('<p>Template class <code>MyImportExport</code> (%s), family ABC and Clarion. Three templates, generated '
        'from <code>template\\win\\MyImportExport.tpl</code> and <code>.tpw</code>:</p>' % esc(TPLVER))
    add(table(['Template', 'Kind', 'What it is for'], [
        ['<code>%s</code>' % t['name'], t['kind'].title(), esc(t['title'].split(' - ', 1)[-1])] for t in TEMPLATES]))
    add('''<p>Add the global extension first: the other two require it. Every table in the dictionary is
offered unless you exclude it, so a table added to the dictionary next year shows up in the window after
the next generate, with no other change.</p>''')

    g = byname['MyImportExportGlobal']
    add('<h2 id="global"><span class="k">Extension</span>MyImportExportGlobal</h2>')
    add('<p>An application extension. Add it once to every app &mdash; in a multi-DLL suite, to each app of the '
        'suite. Its tabs:</p>')
    for tab in sorted(set(p['tab'] for p in g['prompts']), key=lambda x: [p['tab'] for p in g['prompts']].index(x)):
        add('<h3 id="g-%s">%s tab</h3>' % (slug(tab), esc(tab)))
        if (g['name'], tab) in TAB_NOTES: add('<p>%s</p>' % esc(TAB_NOTES[(g['name'], tab)]))
        add(prompt_table(g, tab))
    add(note('cla', 'Expressions in the prompts', '<p>Start <b>Helper program</b> or <b>INI file</b> with '
        '<code>!</code> to use a variable or expression instead of a literal, e.g. '
        '<code>!GLO:DataPath &amp; \'\\mie.ini\'</code>. A helper name without a folder is looked up beside the '
        'program at run time.</p>'))
    add('<h3 id="g-writes">What it generates</h3>')
    add(table(['Where', 'What'], [
        ['Global includes', "<code>INCLUDE('MyImportExport.inc'),ONCE</code>"],
        ['Project', 'The defines <code>_MIEDllMode_</code> / <code>_MIELinkMode_</code>, the DOS driver, the module <code>&lt;program&gt;_MIE.clw</code>, and, if ticked, the helper with <i>copy to output</i>.'],
        ['Global MAP', '<code>MIE_ImportExport(STRING,BYTE=0),BYTE,PROC</code> and <code>MIE_ExportTables(&lt;STRING&gt;),BYTE,PROC</code> &mdash; with <code>,DLL</code> in apps that do not generate them.'],
        ['Used files', 'Every offered table, so ABC declares its <code>Access:</code> and <code>Relate:</code> objects.'],
        ['DLL export list', '<code>MIE_ImportExport</code>, <code>MIE_ExportTables</code>, and in the DLL that holds the class, its VMT, type descriptor and every non-private method &mdash; computed from the .inc at generate time.'],
    ]))
    add('<h3 id="g-module">The generated module</h3>')
    add('<p>The module <code>&lt;program&gt;_MIE.clw</code> holds one class bound to your dictionary, '
        '<code>MIE_DictClass</code>, and the two procedures that use it. Abridged from a real one:</p>')
    add(code(S_GENPROC))
    add('<h3 id="g-hooks">The ABC hooks</h3>')
    add('<p>In an ABC app <code>MIE_DictClass</code> routes the table I/O through the table\'s FileManager and '
        'RelationManager. <code>FM</code> and <code>RM</code> are set per table in <code>SetupTable</code>, so the hooks need no '
        '<code>CASE</code>:</p>')
    add(table(['Hook', 'Generated as'], [
        ['<code>OpenTable</code>', '<code>FM.Open()</code> (or <code>RM.Open()</code> with RelationManager deletes) + <code>FM.UseFile()</code>; opens and closes are counted.'],
        ['<code>CloseTable</code>', '<code>FM.Close()</code> / <code>RM.Close()</code>'],
        ['<code>PrimeRecord</code>', '<code>FM.PrimeRecord()</code> &mdash; clears the buffer and primes auto-increment'],
        ['<code>CancelPrime</code>', '<code>FM.CancelAutoInc()</code>'],
        ['<code>InsertRecord</code>', '<code>FM.TryInsert()</code>; a plain <code>ADD</code> when the key column is mapped on an auto-increment table, so imported IDs are kept'],
        ['<code>UpdateRecord</code>', '<code>FM.TryUpdate()</code>'],
        ['<code>FetchRecord</code>', '<code>FM.TryFetch(SELF.TableKey)</code>'],
        ['<code>DeleteRecord</code>', '<code>FM.DeleteRecord(0)</code> (no cascade), or <code>RM.Delete(0)</code> (dictionary RI)'],
        ['<code>ValidateRecord</code>, <code>ExportFilter</code>', 'Your embeds: one for any table, one per table'],
    ]))
    add('<p>In a Clarion (Legacy) app only <code>ValidateRecord</code> and <code>ExportFilter</code> are '
        'generated; the class\'s own raw-driver hooks do the I/O.</p>')
    add('<h3 id="g-fields">Which fields are offered</h3>')
    add(table(['Dictionary item', 'Result'], [
        ['A field', 'One <code>AddField</code>. Column name: the external <code>NAME()</code> if set, else the label without its prefix.'],
        ['A <code>DIM()</code> array', 'One column per element: <code>CUS:Phones[1]</code> &rarr; <code>Phones_1</code>.'],
        ['Fields inside a plain GROUP', 'Offered one by one; the GROUP itself is not.'],
        ['MEMO, BLOB', 'Not offered.'],
        ['A field declared <code>OVER()</code>, or anything inside an OVER or DIM group', 'Not offered (it would duplicate another field).'],
        ['<code>MIEEXCLUDE</code> in a field\'s or GROUP\'s User Options', 'Not offered.'],
        ['<code>MIEEXCLUDE</code> in a table\'s User Options, or ticked under Exclude tables', 'The whole table is left out.'],
        ['ALIAS tables', 'Left out: the real table is offered instead.'],
        ['The picture', 'The dictionary picture; when there is none, one by type (<code>@d10-</code>, <code>@t4</code>, <code>@s255</code>, <code>@n-21.2</code> ...).'],
        ['<code>pIsKey</code>', '1 for the components of the primary key.'],
    ]))

    add('<h3 id="g-multi">MIE_ExportTables</h3>')
    add('''<p>The second generated procedure exports several tables into one file: a sheet per table in XLSX
and XLS, a collection per table in JSON, an element per table in XML, and a file per table for CSV and TSV.
It offers every table <code>MIE_ImportExport</code> offers and remembers the ticked tables, the format and
the file in the <code>[MIE__Tables]</code> INI section. Pass table labels to pre-tick them:</p>''')
    add(code("MIE_ExportTables()                                ! last selection\n"
             "MIE_ExportTables('Customer, Product, Invoice')    ! exactly these, any case"))
    add('<p>Each table is exported with the columns, order and headers saved for it in '
        '<code>MIE_ImportExport</code>, and the rule embeds (<code>ExportFilter</code>) apply per table as '
        'usual.</p>')
    c = byname['MyImportExportButtons']
    add('<h2 id="buttons"><span class="k">Control</span>MyImportExportButtons</h2>')
    add('<p>A window control template: an <b>Import...</b> and an <b>Export...</b> button, and optionally an '
        '<b>Export tables...</b> button for several tables at once. The one-button style pops a menu with all '
        'three. You can put several on one window, each for a different table.</p>')
    add(prompt_table(c, 'General'))
    add('''<p><b>Procedure's primary table</b> is the table of the first browse on the window, else the form's
table. When neither exists the user picks a table at run time. After a successful import the window is
refreshed: <code>ThisWindow.Reset(1)</code> in ABC, which re-reads every browse.</p>''')
    add(code("CASE POPUP('&Import...|E&xport...')        ! one-button style\n"
             "OF 1\n"
             "  IF MIE_ImportExport('Customer',MIE:Mode:Import)\n"
             "    ThisWindow.Reset(1)\n"
             "  END\n"
             "OF 2\n"
             "  MIE_ImportExport('Customer',MIE:Mode:Export)\n"
             "OF 3\n"
             "  MIE_ExportTables()\n"
             "END"))

    k = byname['MyImportExportCall']
    add('<h2 id="call"><span class="k">Code</span>MyImportExportCall</h2>')
    add('<p>A code template for any embed: a menu item, a button of your own, a process. It writes one call to '
        '<code>MIE_ImportExport</code>, or to <code>MIE_ExportTables</code> in the <i>Export several tables</i> '
        'mode (the table prompt is then ignored).</p>')
    add(prompt_table(k, ''))
    add(code("LOC:Done = MIE_ImportExport('',0)             ! picker, user chooses the mode\n"
             "IF LOC:Done\n"
             "  ThisWindow.Reset(1)\n"
             "END"))

    add('<h2 id="embeds"><span class="k">Embeds</span>Embed points</h2>')
    add('<p>All of them sit in the generated module, under <b>MyImportExport</b> in the global embed tree. '
        'Per-table embeds are only written when you fill them.</p>')
    add(table(['Embed', 'Tree', 'Where it runs'], [
        ['<code>%s</code>' % esc(e['id']), esc(' › '.join(e['tree'][1:])),
         esc(e['desc']) + (' <i>(one per table)</i>' if e['perfile'] else '')] for e in EMBEDS]))
    add(code("! ValidateRecord - Customer\nIF CUS:Country = '' THEN CUS:Country = 'CH'.\n"
             "IF CUS:Email = '' THEN ReturnValue = 1.        ! skip this row"))

    add('<h2 id="multidll"><span class="k">Recipes</span>Multi-DLL suites</h2>')
    add('''<ol class="b">
<li>Add <code>MyImportExportGlobal</code> to <b>every</b> app. An app without it compiles its own copy of the class.</li>
<li>In the data DLL (External: none) tick <b>Generate MIE_ImportExport</b>. The class is compiled in and exported, and so is the procedure.</li>
<li>In the other DLLs and the EXE (External: all, from a DLL) leave it unticked. They import both from the data DLL &mdash; add its <code>.LIB</code> to their projects, as for any DLL procedure.</li>
<li>Put <code>MIEConvert.exe</code> beside the EXE.</li>
</ol>''')
    add(table(['App', '_MIEDllMode_', '_MIELinkMode_'], [
        ['Single EXE, or the data DLL', '0', '1'],
        ['DLLs and EXE that use it', '1', '0'],
    ]))
    add('<h2 id="regen"><span class="k">Recipes</span>After a dictionary change</h2>')
    add('<p>Regenerate the app that generates <code>MIE_ImportExport</code>. New tables and fields appear in the '
        'window; saved mappings for existing tables keep working, and a new field starts out ticked with its '
        'own name as the header.</p>')
    add('<h2 id="next3"><span class="k">Template Guide</span>Where to go next</h2>')
    add(nextcards(['reference.html', 'programmers-guide.html', 'getting-started.html']))

    gtabs = []
    for p in g['prompts']:
        if p['tab'] not in gtabs: gtabs.append(p['tab'])
    nav = [('Overview', [('set', '')]),
           ('Global extension', [('global', '')] + [('g-' + slug(t), '') for t in gtabs] +
                                [('g-writes', ''), ('g-module', ''), ('g-hooks', ''), ('g-fields', ''), ('g-multi', '')]),
           ('Window and code', [('buttons', ''), ('call', ''), ('embeds', '')]),
           ('Recipes', [('multidll', ''), ('regen', ''), ('next3', '')])]
    return page('template-guide.html', 'MyImportExport Template Guide', 'Volume 3', 'Template Guide',
                'Every template, tab, prompt and embed point, and what the generator writes into your app. '
                'The prompt and embed tables are read out of the template source.',
                ['<b>%d</b> templates' % len(TEMPLATES), '<b>%d</b> prompts' % sum(len(t['prompts']) for t in TEMPLATES),
                 '<b>%d</b> embed points' % len(EMBEDS), 'build %s' % esc(BUILDTAG)],
                nav, ''.join(B))


# =====================================================================
#  4  REFERENCE
# =====================================================================
GROUP_BLURB = {
 'Table and fields': 'The table, its key and the field queue that drives everything.',
 'Settings': 'What the window edits. Set them before Export or Import when there is no window.',
 'Results': 'Filled by every Export and Import.',
 'UI': 'Controls the progress reporting writes to.',
 'Internal buffers': 'PROTECTED state of the intermediate-file reader and writer. Listed so a derived class knows what it is looking at.',
 'Methods': 'The calls you make.',
 'Virtual hooks': 'Derive to change how the table is read and written, or to add rules. The template generates ABC versions of the I/O hooks.',
 'Internals': 'PROTECTED helpers the public methods are built from.',
}

def memrow(name, sig, doc, use, tag=''):
    return ('<tr class="fn" data-k="%s"><td class="fn__n"><code>%s</code>%s</td>'
            '<td class="fn__s"><code>%s</code><p class="fn__d">%s</p>%s</td></tr>'
            % (esc((name + ' ' + doc).lower()), esc(name), tag, esc(sig), esc(doc), usecode(use)))

def member_tables(kind):
    out, groups = [], []
    items = PROPLIST if kind == 'p' else METHLIST
    for it in items:
        if it['group'] not in groups: groups.append(it['group'])
    for gname in groups:
        rows = []
        for it in [x for x in items if x['group'] == gname]:
            src = PROPS if kind == 'p' else METHODS
            if it['name'] not in src:
                MISSING.append(it['name']); continue
            doc, use = src[it['name']]
            if kind == 'p':
                sig = it['type'] + ('   ! ' + it['note'] if it['note'] else '')
            else:
                sig = '%s PROCEDURE%s%s' % (it['name'], '(%s)' % it['parms'] if it['parms'] else '',
                                             (',' + it['attrs']) if it['attrs'] else '')
            tag = '<span class="ord">prot</span>' if it['protected'] else ''
            rows.append(memrow(it['name'], sig, doc, use, tag))
        hid = '%s-%s' % (kind, slug(gname))
        out.append('<h3 id="%s">%s</h3>' % (hid, esc(gname)))
        if gname in GROUP_BLURB: out.append('<p>%s</p>' % esc(GROUP_BLURB[gname]))
        out.append('<div class="tw"><table class="fns"><tbody>%s</tbody></table></div>' % ''.join(rows))
    return ''.join(out), groups

def build_reference():
    B = []
    add = B.append
    add('<h2 id="cls"><span class="k">Clarion</span>MyImportExportClass</h2>')
    add('''<p>Declared in <code>MyImportExport.inc</code>, implemented in <code>MyImportExport.clw</code>.
Every entry below is read out of the header, so the declarations here are the ones in the build, and each
carries a worked piece of Clarion. Members marked <span class="ord">prot</span> are PROTECTED: visible to a
derived class only.</p>''')
    add(code("MIE   MyImportExportClass                  ! or derive: CLASS(MyImportExportClass)"))
    add('<h2 id="props"><span class="k">Class</span>Properties</h2>')
    ptables, pgroups = member_tables('p')
    add(ptables)
    add('<h2 id="meths"><span class="k">Class</span>Methods</h2>')
    mtables, mgroups = member_tables('m')
    add(mtables)

    add('<h2 id="queues"><span class="k">Types</span>Queue types</h2>')
    add('<p>Declared in the same header. The class holds one of each, as <code>&amp;</code> references.</p>')
    for q in QUEUES:
        add('<h3 id="q-%s">%s</h3>' % (slug(q['name']), esc(q['name'])))
        if q['doc']: add('<p>%s.</p>' % esc(q['doc']))
        add(table(['Field', 'Type', 'Meaning'],
                  [['<code>%s</code>' % esc(f['name']), '<code>%s</code>' % esc(f['type']), esc(f['note'])]
                   for f in q['fields']]))

    add('<h2 id="eq"><span class="k">Equates</span>Equates</h2>')
    rows = []
    for e in EQUATELIST:
        if e['name'] not in EQUATES: MISSING.append(e['name']); continue
        rows.append(['<code>%s</code>' % esc(e['name']), '<span class="v">%s</span>' % e['value'], esc(EQUATES[e['name']])])
    add(table(['Equate', 'Value', 'Meaning'], rows, 'eq'))

    add('<h2 id="proc"><span class="k">Generated</span>MIE_ImportExport</h2>')
    add('<p>Generated by the global extension; prototyped in the global MAP.</p>')
    add(code("MIE_ImportExport(STRING pTable,BYTE pMode=0),BYTE,PROC"))
    add(table(['Parameter', 'Meaning'], [
        ['<code>pTable</code>', 'The table\'s label in the dictionary, any case. Blank shows a table picker.'],
        ['<code>pMode</code>', '<code>0</code> lets the user choose, <code>MIE:Mode:Export</code> or <code>MIE:Mode:Import</code> opens on that mode.'],
        ['returns', '1 when something was imported or exported, 0 when the user cancelled or it failed.'],
    ]))
    add(usecode("IF MIE_ImportExport('Customer', MIE:Mode:Import) THEN BRW1.ResetSort(1)."))
    add('<h3 id="proc-multi">MIE_ExportTables</h3>')
    add('<p>Generated beside it: the multi-table export window over every offered table.</p>')
    add(code("MIE_ExportTables(<STRING pTables>),BYTE,PROC"))
    add(table(['Parameter', 'Meaning'], [
        ['<code>pTables</code>', 'Optional comma-separated table labels to tick; omitted, the tables ticked last time are ticked.'],
        ['returns', '1 when something was exported, 0 when the user cancelled or it failed.'],
    ]))
    add(usecode("MIE_ExportTables('Customer,Product,Invoice')     ! pre-ticked, user picks format and file"))

    add('<h2 id="helper"><span class="k">Helper</span>MIEConvert.exe</h2>')
    add('<p>The class runs it for you, but it is an ordinary command-line program and can be used from scripts. '
        'Exit code 0 is success, 1 an error; the message goes to <code>--errfile</code> and to stderr. Its own '
        'usage text:</p>')
    add(code(HELPER_USAGE, 'usage'))
    add('<h3 id="h-cmds">Commands</h3>')
    add(table(['Command', 'Reads', 'Writes'], [
        ['<code>sheets</code>', 'an .xls or .xlsx file', 'a text file, one sheet name per line'],
        ['<code>import</code>', 'a file in any of the six formats', 'the intermediate tab file (header row, then data)'],
        ['<code>export</code>', 'the intermediate tab file (header row, type row, data)', 'a file in any of the six formats'],
        ['<code>exportmulti</code>', 'a list file: one <code>name&lt;TAB&gt;intermediate file</code> line per table',
         'one json (a collection per table), xml (an element per table), xlsx or xls (a sheet per table) file'],
    ]))
    add('<h3 id="h-opts">Options</h3>')
    rows = []
    for o in HELPER_OPTS:
        if o not in OPTIONS: MISSING.append('--' + o); continue
        rows.append(['<code>--%s</code>' % o, esc(OPTIONS[o][0]), esc(OPTIONS[o][1])])
    add(table(['Option', 'Commands', 'Meaning'], rows))
    add(code('MIEConvert export data.tsv out.xlsx --sheet "Customers" --replacesheet\n'
             'MIEConvert import "C:\\in\\orders.json" rows.tsv --rowpath items --maxrows 5', 'shell'))

    add('<h2 id="next4"><span class="k">Reference</span>Where to go next</h2>')
    add(nextcards(['programmers-guide.html', 'template-guide.html', 'getting-started.html']))

    nav = [('Class', [('cls', '')]),
           ('Properties', [('props', '')] + [('p-' + slug(g), '') for g in pgroups]),
           ('Methods', [('meths', '')] + [('m-' + slug(g), '') for g in mgroups]),
           ('Types', [('queues', '')] + [('q-' + slug(q['name']), '') for q in QUEUES] + [('eq', '')]),
           ('Procedure and helper', [('proc', ''), ('proc-multi', ''), ('helper', ''), ('h-cmds', ''), ('h-opts', ''), ('next4', '')])]
    return page('reference.html', 'MyImportExport Reference', 'Volume 4', 'Reference',
                'Every property, method, equate and helper option &mdash; generated from the sources, with a '
                'worked piece of Clarion against each member.',
                ['<b>%d</b> methods' % len(METHLIST), '<b>%d</b> properties' % len(PROPLIST),
                 '<b>%d</b> equates' % len(EQUATELIST), '<b>%d</b> helper options' % len(HELPER_OPTS)],
                nav, ''.join(B), showfilter=True)


# =====================================================================
if __name__ == '__main__':
    total = 0
    for fn, size in (('getting-started.html',   build_getting_started()),
                     ('programmers-guide.html', build_programmers_guide()),
                     ('template-guide.html',    build_template_guide()),
                     ('reference.html',         build_reference())):
        print('  docs/%-24s %6.1f KB' % (fn, size / 1024.0))
        total += size
    print('  %-26s %6.1f KB' % ('four volumes', total / 1024.0))
    bad = False
    if MISSING:
        print('  !! no entry in usage.py for: ' + ', '.join(sorted(set(MISSING)))); bad = True
    else:
        print('  every member, equate and option has its entry')
    if PROBLEMS:
        for line in PROBLEMS: print('  !! ' + line)
        bad = True
    else:
        print('  every nav entry names the heading it lands on')
    sys.exit(1 if bad else 0)
