"""Argon UI v2 final palette generator + WCAG validator.

Derives every v2 colour token for the 12 built-in themes from a small seed per theme
(the v1 accent set is kept exactly), validates the contrast targets in DESIGN_V2.md
section 2.4, adjusts derived tokens that fail, and writes:
  tools/palette.json   (token -> hex, per theme; read by tools/gen_palette_data.luau)
and prints the markdown tables used in design/v2/DESIGN_V2.md section 2.3.
Run: python -I tools/gen_palette.py   (from the repository root)
Then: lune run tools/gen_palette_data.luau   (writes src/theme/PaletteData.luau)
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))

def hx(h):
    h = h.lstrip('#'); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
def tohex(c):
    return '#%02X%02X%02X' % tuple(max(0, min(255, round(v))) for v in c)
def lin(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
def lum(c):
    r, g, b = c; return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
def cr(a, b):
    la, lb = lum(a), lum(b)
    if la < lb: la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)
def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
def over(fg, bg, transparency):
    """Roblox compositing: a Frame of colour fg at BackgroundTransparency T over bg."""
    a = 1 - transparency
    return tuple(fg[i] * a + bg[i] * (1 - a) for i in range(3))

WHITE, BLACK = (255, 255, 255), (0, 0, 0)

def step_to(base, toward, against, target, start=0.0, inc=0.01):
    """Move base toward `toward` until contrast(result, against) >= target."""
    t = start
    c = mix(base, toward, t)
    while cr(c, against) < target and t < 1:
        t += inc; c = mix(base, toward, t)
    return c

# Seeds. Frame/Sheet/Raised bases follow the Depth direction; accents are the v1 values
# (Argon.Themes.*.Accent/AccentLight/AccentDark), AccentAlt is used only on progress bars.
SEEDS = {
 'Argon':    dict(frame=(12,14,22),  sheet=(17,19,28), accent='#9970FF', hi='#C3AAFF', deep='#5C3DB8', alt='#45C8FF', text='#F1F3F9', muted='#969DB1'),
 'Amethyst': dict(frame=(16,11,26),  sheet=(22,16,34), accent='#A76DFF', hi='#D2B2FF', deep='#672DB7', alt='#F472B6', text='#F5F0FF', muted='#B2A3CD'),
 'Midnight': dict(frame=(8,12,21),   sheet=(12,18,29), accent='#58A6FF', hi='#9BCDFF', deep='#235BB4', alt='#7C8CFF', text='#EEF4FF', muted='#929FB5'),
 'Emerald':  dict(frame=(8,15,14),   sheet=(12,21,20), accent='#34D399', hi='#97F6D3', deep='#0F7658', alt='#38BDF8', text='#EEF9F6', muted='#91ABA4'),
 'Rose':     dict(frame=(19,10,16),  sheet=(25,14,21), accent='#F472B6', hi='#FBB6DC', deep='#BE185D', alt='#FB923C', text='#FFEFF8', muted='#BC94AB'),
 'Slate':    dict(frame=(13,16,20),  sheet=(18,22,28), accent='#7DC4FF', hi='#BADEFF', deep='#3478BA', alt='#94A3B8', text='#EEF3F9', muted='#9AA6B6'),
 'Ember':    dict(frame=(18,11,8),   sheet=(24,16,12), accent='#FF8A4C', hi='#FFBE96', deep='#BE4A1A', alt='#FFD166', text='#FFF1E9', muted='#C4A392'),
 'Nord':     dict(frame=(30,34,43),  sheet=(37,42,53), accent='#88C0D0', hi='#BEE0E8', deep='#4C8498', alt='#81A1C1', text='#ECEFF4', muted='#B1BBC9'),
 'Mono':     dict(frame=(12,12,14),  sheet=(18,18,20), accent='#E2E2E8', hi='#FFFFFF', deep='#8C8C96', alt='#A1A1AA', text='#F4F4F6', muted='#9F9FA8'),
 'Ocean':    dict(frame=(7,16,24),   sheet=(11,22,31), accent='#38BDD0', hi='#96E7F0', deep='#116E82', alt='#60A5FA', text='#E9F6FC', muted='#92AFC0'),
}
STATUS_DARK = dict(Success='#4ADEA2', Warning='#F7BE4F', Danger='#FF657C', Info='#60A5FA')

def derive_dark(name, s):
    frame, sheet = s['frame'], s['sheet']
    text = hx(s['text'])
    t = {}
    t['Frame'] = frame
    t['Sheet'] = sheet
    # Platter: a fill step of >= 1.15:1 over the sheet (fill steps, not hairlines, separate surfaces).
    surface = step_to(sheet, WHITE, sheet, 1.15, inc=0.004)
    t['Surface'] = surface
    t['Hover'] = step_to(surface, WHITE, surface, 1.12, inc=0.004)
    t['Active'] = step_to(surface, WHITE, surface, 1.26, inc=0.004)
    t['Raised'] = step_to(sheet, WHITE, sheet, 1.22, inc=0.004)
    t['Well'] = mix(frame, BLACK, 0.25)
    t['Track'] = step_to(surface, text, surface, 1.65, start=0.10)
    t['Border'] = step_to(surface, text, surface, 1.45, start=0.08)
    t['BorderSoft'] = step_to(surface, text, surface, 1.18, start=0.03)
    t['Text'] = text
    t['Text2'] = step_to(mix(text, surface, 0.22), text, surface, 9.0)
    muted = hx(s['muted'])
    for against, target in ((surface, 5.2), (t['Hover'], 4.7), (t['Raised'], 4.7)):
        muted = step_to(muted, text, against, target)
    t['Muted'] = muted
    dim = mix(muted, surface, 0.30)
    for against, target in ((surface, 3.6), (t['Well'], 4.5)):
        dim = step_to(dim, text, against, target)
    t['Dim'] = dim
    t['Disabled'] = mix(surface, muted, 0.42)
    acc, hi, deep, alt = hx(s['accent']), hx(s['hi']), hx(s['deep']), hx(s['alt'])
    t['Accent'], t['AccentHi'], t['AccentDeep'], t['AccentAlt'] = acc, hi, deep, alt
    t['AccentText'] = step_to(acc, WHITE, surface, 6.0)
    ink = mix(frame, BLACK, 0.4)
    worst_dark = min(cr(ink, acc), cr(ink, hi))
    worst_white = min(cr(WHITE, acc), cr(WHITE, hi))
    t['OnAccent'] = ink if worst_dark >= worst_white else WHITE
    t['AccentSoft'] = mix(surface, acc, 0.16)
    t['Focus'] = step_to(hi, WHITE, sheet, 3.0)
    for k, v in STATUS_DARK.items():
        c = hx(v)
        t[k] = c
        t[k + 'Soft'] = mix(surface, c, 0.15)
    t['OnStatus'] = mix(frame, BLACK, 0.4)
    return t

def light_theme():
    t = {}
    t['Frame'] = (229, 231, 239); t['Sheet'] = (243, 244, 248); t['Surface'] = (255, 255, 255)
    t['Hover'] = (240, 241, 246); t['Active'] = (229, 231, 239); t['Raised'] = (255, 255, 255)
    t['Well'] = (243, 244, 248); t['Track'] = (196, 200, 213); t['Border'] = (208, 212, 224); t['BorderSoft'] = (231, 233, 240)
    t['Text'] = hx('#12141C'); t['Text2'] = hx('#363B4A'); t['Muted'] = hx('#565C70'); t['Dim'] = hx('#6B7186')
    t['Disabled'] = (170, 175, 190)
    t['Accent'] = hx('#6B4AE6'); t['AccentHi'] = hx('#8466F0'); t['AccentDeep'] = hx('#5233C9'); t['AccentAlt'] = hx('#1597D4')
    t['AccentText'] = hx('#5233C9'); t['OnAccent'] = WHITE
    t['AccentSoft'] = mix(WHITE, t['Accent'], 0.10)
    t['Focus'] = hx('#5233C9')
    for k, v in dict(Success='#14975E', Warning='#B4730C', Danger='#D62E4B', Info='#2F74D0').items():
        t[k] = hx(v); t[k + 'Soft'] = mix(WHITE, hx(v), 0.10)
    t['OnStatus'] = WHITE
    return t

def hc_theme():
    t = {}
    t['Frame'] = (0, 0, 0); t['Sheet'] = (0, 0, 0); t['Surface'] = (17, 17, 17)
    t['Hover'] = (38, 38, 38); t['Active'] = (52, 52, 52); t['Raised'] = (17, 17, 17)
    t['Well'] = (0, 0, 0); t['Track'] = (112, 112, 112); t['Border'] = (150, 150, 150); t['BorderSoft'] = (96, 96, 96)
    t['Text'] = WHITE; t['Text2'] = (240, 240, 240); t['Muted'] = (214, 214, 214); t['Dim'] = (180, 180, 180)
    t['Disabled'] = (120, 120, 120)
    t['Accent'] = hx('#FFE14D'); t['AccentHi'] = hx('#FFF08A'); t['AccentDeep'] = hx('#E6C200'); t['AccentAlt'] = hx('#FFE14D')
    t['AccentText'] = hx('#FFE14D'); t['OnAccent'] = BLACK; t['AccentSoft'] = (51, 45, 15)
    t['Focus'] = hx('#FFE14D')
    for k, v in dict(Success='#5CF2A6', Warning='#FFC24D', Danger='#FF7A8C', Info='#7DBBFF').items():
        t[k] = hx(v); t[k + 'Soft'] = mix((17, 17, 17), hx(v), 0.22)
    t['OnStatus'] = BLACK
    return t

THEMES = {}
for n, s in SEEDS.items():
    THEMES[n] = derive_dark(n, s)
THEMES['Daylight'] = light_theme()
THEMES['HighContrast'] = hc_theme()

# Validator fix-ups shared by every theme (the same rules Theme.derive applies to AddTheme palettes):
for n, t in THEMES.items():
    for k in ('Success', 'Warning', 'Danger', 'Info'):
        t[k] = step_to(t[k], t['Text'], t['Surface'], 4.5)        # status fg readable as text
    t['Dim'] = step_to(t['Dim'], t['Text'], t['Well'], 4.5)        # placeholders in wells
    if cr(t['OnAccent'], t['AccentHi']) < 4.5:                      # gradient top stop must hold the ink
        t['AccentHi'] = step_to(t['AccentHi'], t['Accent'] if t['OnAccent'] == WHITE else WHITE, t['OnAccent'], 4.5)

ORDER = ['Frame','Sheet','Surface','Hover','Active','Raised','Well','Track','Border','BorderSoft',
         'Text','Text2','Muted','Dim','Disabled','Accent','AccentHi','AccentDeep','AccentAlt','AccentText',
         'OnAccent','AccentSoft','Focus','Success','Warning','Danger','Info','SuccessSoft','WarningSoft',
         'DangerSoft','InfoSoft','OnStatus']

CHECKS = [
 ('Text','Surface',10.0), ('Text2','Surface',9.0), ('Muted','Surface',4.8), ('Muted','Hover',4.5),
 ('Muted','Raised',4.5), ('Dim','Surface',3.5), ('Dim','Well',4.5), ('AccentText','Surface',4.6),
 ('OnAccent','Accent',4.5), ('OnAccent','AccentHi',4.5), ('Focus','Sheet',3.0), ('Focus','Surface',3.0),
 ('Track','Surface',1.6), ('Border','Surface',1.4), ('Surface','Sheet',1.08), ('Hover','Surface',1.06),
 ('Danger','Surface',4.5), ('Success','Surface',4.5), ('Warning','Surface',4.5), ('Info','Surface',4.5),
]

def glass(t, T, scene):
    return over(t['Frame'], scene, T)

out = {}
rows = []
fails = []
for name, t in THEMES.items():
    out[name] = {k: tohex(t[k]) for k in ORDER}
    r = {}
    for a, b, target in CHECKS:
        v = cr(t[a], t[b]); r[f'{a}/{b}'] = round(v, 2)
        if v + 1e-9 < target and not (name == 'Daylight' and (a, b) in (('Surface','Sheet'),)):
            fails.append((name, a, b, round(v, 2), target))
    # text on glass (sidebar) over a pure white scene and a pure black scene
    for T in (0.14, 0.25):
        for scene_name, scene in (('white', WHITE), ('black', BLACK)):
            g = glass(t, T, scene)
            r[f'Text2/glass{int(T*100)}-{scene_name}'] = round(cr(t['Text2'], g), 2)
            r[f'Muted/glass{int(T*100)}-{scene_name}'] = round(cr(t['Muted'], g), 2)
    out[name]['_contrast'] = r

with open(os.path.join(HERE, 'palette.json'), 'w') as f:
    json.dump(out, f, indent=1)

# markdown
md = []
md.append('| Token | ' + ' | '.join(THEMES.keys()) + ' |')
md.append('|---|' + '---|' * len(THEMES))
for k in ORDER:
    md.append(f'| `{k}` | ' + ' | '.join(out[n][k] for n in THEMES) + ' |')
md.append('')
md.append('| Pair (target) | ' + ' | '.join(THEMES.keys()) + ' |')
md.append('|---|' + '---|' * len(THEMES))
for a, b, target in CHECKS:
    md.append(f'| {a} on {b} (>= {target}) | ' + ' | '.join(f"{out[n]['_contrast'][f'{a}/{b}']:.2f}" for n in THEMES) + ' |')
for key in ('Text2/glass14-white','Text2/glass25-white','Muted/glass14-white','Text2/glass14-black'):
    md.append(f'| {key} | ' + ' | '.join(f"{out[n]['_contrast'][key]:.2f}" for n in THEMES) + ' |')
with open(os.path.join(HERE, 'v2_final_palette.md'), 'w') as f:
    f.write('\n'.join(md) + '\n')
print('\n'.join(md))
print('FAILS:', fails)
