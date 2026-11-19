#!/usr/bin/env python3
"""Merges translation files into the app's String Catalogs.

Input:  <dir>/out-<lang>.json — {"English key": "translation" | {"one": …, "other": …}} per language
        (plural forms use CLDR categories). The key "NSCameraUsageDescription" goes to InfoPlist.xcstrings.
Output: ios/BestMove/Resources/Localizable.xcstrings and InfoPlist.xcstrings (updated in place).

Checks every translation keeps the source's placeholders (%@, %lld) and that plural entries have
an "other" form. Usage: ios/scripts/merge-translations.py <dir-with-out-files>
"""
import json
import re
import sys
from pathlib import Path

RES = Path(__file__).resolve().parents[1] / 'BestMove' / 'Resources'
CATALOG = RES / 'Localizable.xcstrings'
INFOPLIST = RES / 'InfoPlist.xcstrings'
CAMERA_EN = 'Best Move uses the camera to photograph a chess board so it can read the position. Photos stay on your device.'
NOT_TRANSLATED = {'', '%lld', 'Best Move', 'Stockfish 19', 'rnbqkbnr/pppppppp/8/…'}
# Templates made only of arguments: Foundation isolates each argument (FSI…PDI), so with no letters
# of its own the paragraph would default to left-to-right; Arabic needs a right-to-left mark.
# Chinese and Japanese end sentences with "。" and use no space.
TEMPLATES = {'%@ %@.': {'ar': '\u200f%@ %@.', 'ja': '%@%@。', 'zh-Hans': '%@%@。'}}
# English needs its own plural forms for this one.
EN_PLURALS = {
    '%lld squares look uncertain — outlined on the board. Tap a piece below, then a square to fix it.': {
        'one': '%lld square looks uncertain — outlined on the board. Tap a piece below, then a square to fix it.',
        'other': '%lld squares look uncertain — outlined on the board. Tap a piece below, then a square to fix it.',
    },
}
PLACEHOLDER = re.compile(r'%(?:lld|@|d)')


def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def localization(value):
    if isinstance(value, dict):
        return {'variations': {'plural': {cat: unit(text) for cat, text in value.items()}}}
    return unit(value)


def check(lang, key, source, value, problems):
    forms = value.values() if isinstance(value, dict) else [value]
    if isinstance(value, dict) and 'other' not in value:
        problems.append(f'{lang}: plural without "other": {key!r}')
    want = sorted(PLACEHOLDER.findall(source))
    categories = value.items() if isinstance(value, dict) else [('other', value)]
    for category, form in categories:
        if not isinstance(form, str) or not form.strip():
            problems.append(f'{lang}: empty translation: {key!r}')
        elif sorted(PLACEHOLDER.findall(form)) != want:
            # "one"/"two"/"zero" may spell the number out instead ("nur eine", "نقلتين").
            if not (category in ('zero', 'one', 'two') and not PLACEHOLDER.findall(form)):
                problems.append(f'{lang}: placeholders differ: {key!r} -> {form!r}')


def main(src_dir):
    catalog = json.loads(CATALOG.read_text())
    strings = catalog['strings']
    files = sorted(Path(src_dir).glob('out-*.json'))
    problems = []
    camera = {}
    for f in files:
        lang = f.stem[len('out-'):]
        data = json.loads(f.read_text())
        camera[lang] = data.pop('NSCameraUsageDescription', None)
        missing = [k for k in strings if k not in NOT_TRANSLATED and k not in TEMPLATES and k not in data]
        if missing:
            problems.append(f'{lang}: {len(missing)} keys missing, e.g. {missing[:3]}')
        for key, value in data.items():
            if key not in strings or key in NOT_TRANSLATED or key in TEMPLATES:
                continue
            check(lang, key, key, value, problems)
            strings[key].setdefault('localizations', {})[lang] = localization(value)
        print(f'{lang}: {len(data)} strings')
    for key in NOT_TRANSLATED & strings.keys():
        strings[key]['shouldTranslate'] = False
        strings[key].pop('localizations', None)
    for key, per_lang in TEMPLATES.items():
        if key in strings:
            strings[key].pop('shouldTranslate', None)
            for lang, value in per_lang.items():
                strings[key].setdefault('localizations', {})[lang] = localization(value)
    for key, forms in EN_PLURALS.items():
        if key in strings:
            strings[key].setdefault('localizations', {})['en'] = localization(forms)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n')

    info = {'sourceLanguage': 'en', 'version': '1.0', 'strings': {'NSCameraUsageDescription': {
        'comment': 'Privacy - Camera Usage Description', 'extractionState': 'manual',
        'localizations': {'en': unit(CAMERA_EN)}}}}
    for lang, text in camera.items():
        if text:
            check(lang, 'NSCameraUsageDescription', CAMERA_EN, text, problems)
            info['strings']['NSCameraUsageDescription']['localizations'][lang] = unit(text)
    INFOPLIST.write_text(json.dumps(info, ensure_ascii=False, indent=2, sort_keys=True) + '\n')

    print(f'{len(files)} languages merged into {CATALOG.name} and {INFOPLIST.name}')
    if problems:
        print('PROBLEMS:\n  ' + '\n  '.join(problems))
        sys.exit(1)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
