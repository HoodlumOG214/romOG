"""
Write platforms.yml with three-tier RA source strategy:
  1. internet_archive -> RetroAchievementsSets (Apr 2026, login required, primary)
  2. ra_collection_v5 -> v5 JSON index (Jul 2024, public, secondary)
  3. internet_archive -> original flat IA items (tertiary, disc systems)
"""
import yaml
from pathlib import Path

RA_SETS = 'https://archive.org/download/RetroAchievementsSets'

def ra_sets(folder, fmt, filter_ext='zip|7z', extra_parsers=None):
    parsers = {'libretro': {}, 'no_intro': {}}
    if extra_parsers:
        parsers.update(extra_parsers)
    return {
        'source': 'internet_archive',
        'format': fmt,
        'urls': [f'{RA_SETS}/{folder}/'],
        'filter': rf'(.*)\.(${filter_ext})',
        'type': 'Game',
        'parsers': parsers,
    }

def ra_v5(ra_system, fmt, extra_parsers=None):
    parsers = {'libretro': {}, 'no_intro': {}}
    if extra_parsers:
        parsers.update(extra_parsers)
    return {
        'source': 'ra_collection_v5',
        'format': fmt,
        'urls': [],
        'filter': r'(.*)\.(zip)',
        'type': 'Game',
        'parsers': parsers,
        'ra_system': ra_system,
    }

def ia_flat(url, fmt, filter_ext, extra_parsers=None):
    parsers = {'libretro': {}, 'no_intro': {}}
    if extra_parsers:
        parsers.update(extra_parsers)
    return {
        'source': 'internet_archive',
        'format': fmt,
        'urls': [url],
        'filter': rf'(.*)\.(${filter_ext})',
        'type': 'Game',
        'parsers': parsers,
    }

platforms = {
    'nes': [
        ra_sets('RA%20-%20Nintendo%20Entertainment%20System', 'zip'),
        ra_v5('NES-Famicom', 'zip'),
    ],
    'fds': [
        ra_sets('RA%20-%20Nintendo%20Famicom%20Disk%20System', 'zip'),
        ra_v5('Famicom Disk System', 'zip'),
    ],
    'snes': [
        ra_sets('RA%20-%20Super%20Nintendo%20Entertainment%20System', 'zip'),
        ra_v5('SNES-Super Famicom', 'zip'),
    ],
    'gb': [
        ra_sets('RA%20-%20Nintendo%20Game%20Boy', 'zip'),
        ra_v5('Game Boy', 'zip'),
    ],
    'gbc': [
        ra_sets('RA%20-%20Nintendo%20Game%20Boy%20Color', 'zip'),
        ra_v5('Game Boy Color', 'zip'),
    ],
    'gba': [
        ra_sets('RA%20-%20Nintendo%20Game%20Boy%20Advance', 'zip'),
        ra_v5('Game Boy Advance', 'zip'),
    ],
    'n64': [
        ra_sets('RA%20-%20Nintendo%2064', 'zip'),
        ra_v5('Nintendo 64', 'zip'),
    ],
    'nds': [
        ra_sets('RA%20-%20Nintendo%20DS', 'zip', extra_parsers={'gametdb': {}}),
        ra_v5('Nintendo DS', 'zip', extra_parsers={'gametdb': {}}),
    ],
    'dsi': [
        ra_sets('RA%20-%20Nintendo%20DSi', 'zip'),
    ],
    'min': [
        ra_sets('RA%20-%20Nintendo%20Pokemon%20Mini', 'zip'),
    ],
    'vb': [
        ra_sets('RA%20-%20Nintendo%20Virtual%20Boy', 'zip'),
        ra_v5('Virtual Boy', 'zip'),
    ],
    'sms': [
        ra_sets('RA%20-%20Sega%20Master%20System', 'zip'),
        ra_v5('Master System', 'zip'),
    ],
    'gg': [
        ra_sets('RA%20-%20Sega%20Game%20Gear', 'zip'),
        ra_v5('Game Gear', 'zip'),
    ],
    'smd': [
        ra_sets('RA%20-%20Sega%20Genesis', 'zip'),
        ra_v5('Genesis-Mega Drive', 'zip'),
    ],
    '32x': [
        ra_sets('RA%20-%20Sega%2032X', 'zip'),
        ra_v5('Sega 32X', 'zip'),
    ],
    'sg1k': [
        ra_sets('RA%20-%20Sega%20SG-1000', 'zip'),
    ],
    'a26': [
        ra_sets('RA%20-%20Atari%202600', 'zip'),
        ra_v5('Atari 2600', 'zip'),
        ia_flat('https://archive.org/download/nointro.atari-2600/', 'a26', '7z'),
    ],
    'a78': [
        ra_sets('RA%20-%20Atari%207800', 'zip'),
        ra_v5('Atari 7800', 'zip'),
        ia_flat('https://archive.org/download/nointro.atari-7800/', 'a78', '7z'),
    ],
    'lynx': [
        ra_sets('RA%20-%20Atari%20Lynx', 'zip'),
        ra_v5('Atari Lynx', 'zip'),
        ia_flat('https://archive.org/download/AtariLynxRomCollectionByGhostware/', 'lnx', 'lnx'),
    ],
    'jag': [
        ra_sets('RA%20-%20Atari%20Jaguar', 'zip'),
        ra_v5('Atari Jaguar', 'zip'),
    ],
    'tg16': [
        ra_sets('RA%20-%20NEC%20TurboGrafx-16', 'zip'),
        ra_v5('TurboGrafx-16', 'zip'),
        ia_flat('https://archive.org/download/nointro.tg-16/', 'pce', '7z'),
    ],
    'cv': [
        ra_sets('RA%20-%20Colecovision', 'zip'),
    ],
    'intv': [
        ra_sets('RA%20-%20Mattel%20Intellivision', 'zip'),
    ],
    'ngp': [
        ra_sets('RA%20-%20SNK%20Neo%20Geo%20Pocket', 'zip'),
    ],
    'ws': [
        ra_sets('RA%20-%20WonderSwan', 'zip'),
    ],
    'vec': [
        ra_sets('RA%20-%20GCE%20Vectrex', 'zip'),
    ],
    'o2': [
        ra_sets('RA%20-%20Magnavox%20Odyssey%202', 'zip'),
    ],
    'msx': [
        ra_sets('RA%20-%20Microsoft%20MSX', 'zip'),
    ],
    'pc88': [
        ra_sets('RA%20-%20NEC%20PC-8801', 'zip'),
    ],
    # Disc systems: RetroAchievementsSets primary + separate flat items fallback
    'gc': [
        ra_sets('RA%20-%20Nintendo%20GameCube', 'rvz', extra_parsers={'gametdb': {}}),
        ia_flat('https://archive.org/download/RetroAchievementsGameCube/', 'rvz', 'rvz|iso|zip', {'gametdb': {}}),
        ra_v5('GameCube', 'rvz', extra_parsers={'gametdb': {}}),
    ],
    'wii': [
        ra_sets('RA%20-%20Nintendo%20Wii', 'rvz', extra_parsers={'gametdb': {}}),
        ia_flat('https://archive.org/download/RetroAchievementsWii/', 'rvz', 'rvz|iso|wbfs|zip', {'gametdb': {}}),
    ],
    'ps1': [
        ra_sets('RA%20-%20PlayStation', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsPSX/', 'chd', 'chd|zip|bin'),
        ra_v5('PlayStation', 'chd'),
    ],
    'ps2': [
        ra_sets('RA%20-%20PlayStation%202', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsPS2A_G/', 'chd', 'chd|iso|zip'),
        ia_flat('https://archive.org/download/RetroAchievementsPS2H_R/', 'chd', 'chd|iso|zip'),
        ia_flat('https://archive.org/download/RetroAchievementsPS2S_Z/', 'chd', 'chd|iso|zip'),
        ra_v5('PlayStation 2', 'chd'),
    ],
    'psp': [
        ra_sets('RA%20-%20PlayStation%20Portable', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsPSP/', 'chd', 'chd|iso|zip'),
        ra_v5('PlayStation Portable', 'chd'),
    ],
    'sat': [
        ra_sets('RA%20-%20Sega%20Saturn', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsSaturn/', 'chd', 'chd|zip|bin'),
        ra_v5('Saturn', 'chd'),
    ],
    'dc': [
        ra_sets('RA%20-%20Dreamcast', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsDreamcast/', 'chd', 'chd|zip'),
        ra_v5('Dreamcast', 'chd'),
    ],
    'scd': [
        ra_sets('RA%20-%20Sega%20CD', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsSegaCD/', 'chd', 'chd|zip|bin'),
        ra_v5('Sega CD', 'chd'),
    ],
    'tgcd': [
        ra_sets('RA%20-%20TurboGrafx%20CD', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsTGFXCD/', 'chd', 'chd|zip|bin'),
    ],
    '3do': [
        ra_sets('RA%20-%203DO%20Interactive%20Multiplayer', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievements3DO/', 'chd', 'chd|zip|bin'),
    ],
    'jcd': [
        ra_sets('RA%20-%20Atari%20Jaguar%20CD', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsJaguarCD/', 'chd', 'chd|zip|bin'),
    ],
    'pcfx': [
        ra_sets('RA%20-%20PC-FX', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsPCFX/', 'chd', 'chd|zip|bin'),
    ],
    'ngcd': [
        ra_sets('RA%20-%20Neo%20Geo%20CD', 'chd'),
        ia_flat('https://archive.org/download/RetroAchievementsNeoGeoCD/', 'chd', 'chd|zip|bin'),
    ],
}

out = Path('platforms.yml')
out.write_text(yaml.dump(platforms, default_flow_style=False, sort_keys=False, allow_unicode=True))

total_entries = sum(len(v) for v in platforms.values())
total_urls = sum(len(e['urls']) for v in platforms.values() for e in v)
print(f'Wrote {len(platforms)} platforms, {total_entries} source entries, {total_urls} URLs')
for k, v in platforms.items():
    sources = [e['source'] for e in v]
    print(f'  {k}: {sources}')
