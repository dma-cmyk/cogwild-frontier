"""Build bundled JP subsets with fontTools from the repository root.

Install fontTools in a virtual environment outside the repository, for example:
    python3 -m venv /tmp/cogwild-fontenv && /tmp/cogwild-fontenv/bin/pip install fonttools
    /tmp/cogwild-fontenv/bin/python tools/subset_japanese_fonts.py
"""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
chars = set(range(0x3000, 0x3100)) | set(range(0xFF00, 0xFFF0))
# JIS X 0208 levels 1 and 2, kana, symbols and punctuation.
for row in range(0xA1, 0xFF):
    for cell in range(0xA1, 0xFF):
        try:
            chars.update(map(ord, bytes([row, cell]).decode('euc_jp')))
        except UnicodeDecodeError:
            pass
for path in (ROOT / 'game/data/i18n').rglob('*.json'):
    chars.update(map(ord, path.read_text()))
chars.update(map(ord, 'Language / 言語日本語使い古した錆びたの'))
for weight in ('Regular',):
    font = TTFont('/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc', fontNumber=0)
    assert 'JP' in font['name'].getDebugName(1)
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_legacy = True
    options.name_languages = ['*']
    sub = subset.Subsetter(options=options)
    sub.populate(unicodes=chars)
    sub.subset(font)
    target = ROOT / f'game/assets/fonts/CogwildCJK-{weight}.otf'
    font.save(target)
    print(target.name, target.stat().st_size, 'bytes;', len(font.getBestCmap()), 'glyphs')
license_text = Path('/usr/share/licenses/noto-fonts-cjk/LICENSE').read_text()
(ROOT / 'game/assets/fonts/LICENSE-NotoCJK.txt').write_text('Covers CogwildCJK-Regular.otf, a subset of Noto Sans CJK JP. The CJK bold face is generated at runtime with FontVariation emboldening.\n\n' + license_text)
(ROOT / 'game/assets/fonts/LICENSE-Noto.txt').write_text('Covers NotoSans-Regular.ttf, NotoSans-SemiBold.ttf, NotoSerif-Regular.ttf and NotoSerif-Bold.ttf.\n\n' + license_text)
