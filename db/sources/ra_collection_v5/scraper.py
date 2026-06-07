"""
RetroAchievements Collection v5 source plugin.

Downloads TamperMonkeyRetroachievements.json once per build (cached),
then generates entries for a given platform by matching the system
folder prefix in the file path.

JSON schema:
  { "game_id": [ { "MD5": "System Folder/Game Name/file.zip" } ] }

config.extras['ra_system'] must match the folder prefix exactly,
e.g. "Genesis-Mega Drive" or "Game Boy Advance".
"""
import json
import os
import urllib.request
from typing import Any
from core.contract import BuildContext, PlatformConfig, SourceManifest
from utils.parse_utils import size_bytes_to_str

JSON_URL = 'https://archive.org/download/retroachievements_collection_v5/TamperMonkeyRetroachievements.json'
BASE_URL = 'https://archive.org/download/retroachievements_collection_v5'
HOST_NAME = 'Internet Archive (RA Collection v5)'
CACHE_PATH = 'cache/ra_collection_v5.json'

# Map system folder names in JSON to separate IA items (same as TamperMonkey logic)
SEPARATE_ITEMS = {
    'NES-Famicom':        'retroachievements_collection_NES-Famicom',
    'SNES-Super Famicom': 'retroachievements_collection_SNES-Super_Famicom',
    'PlayStation':        'retroachievements_collection_PlayStation',
    'PlayStation 2':      'retroachievements_collection_PlayStation_2',
    'PlayStation Portable': 'retroachievements_collection_PlayStation_Portable',
    'GameCube':           'retroachievements_collection_GameCube',
}

_json_cache: dict | None = None


def _load_json(use_cached: bool) -> dict:
    global _json_cache
    if _json_cache is not None:
        return _json_cache

    os.makedirs('cache', exist_ok=True)

    if use_cached and os.path.exists(CACHE_PATH):
        print(f'      ra_collection_v5: using cached JSON')
        with open(CACHE_PATH, 'r', encoding='utf-8') as f:
            _json_cache = json.load(f)
        return _json_cache

    print(f'      ra_collection_v5: downloading JSON index...')
    with urllib.request.urlopen(JSON_URL, timeout=60) as r:
        data = r.read()

    with open(CACHE_PATH, 'wb') as f:
        f.write(data)

    _json_cache = json.loads(data)
    print(f'      ra_collection_v5: loaded {len(_json_cache)} game entries')
    return _json_cache


def _make_url(path: str) -> str:
    """Build the correct download URL, respecting separate IA items."""
    parts = path.split('/', 1)
    if not parts:
        return f'{BASE_URL}/{path}'

    system = parts[0]

    # PlayStation 2 split: N-Z vs A-M
    if system == 'PlayStation 2':
        filename = path.split('/')[-1]
        suffix = 'N-Z' if filename[0].upper() >= 'N' else 'A-M'
        item = f'retroachievements_collection_PlayStation_2_{suffix}'
        return f'https://archive.org/download/{item}/{path}'

    if system in SEPARATE_ITEMS:
        item = SEPARATE_ITEMS[system]
        return f'https://archive.org/download/{item}/{path}'

    return f'{BASE_URL}/{path}'


def scrape(ra_system: str, platform: str, source_config: dict, use_cached: bool) -> list[dict[str, Any]]:
    data = _load_json(use_cached)
    fmt = source_config.get('format', 'zip')
    src_type = source_config.get('type', 'Game')

    seen_paths: set[str] = set()
    entries: list[dict] = []

    for game_id, hash_list in data.items():
        if not hash_list:
            continue
        hashes: dict[str, str] = hash_list[0]

        # Collect all files for this game that match our system
        game_files = []
        game_title = None

        for md5, file_path in hashes.items():
            # Skip special markers
            if file_path.startswith(('missing', 'paid', 'ignore')):
                continue

            # FBNeo uses backslash separator
            sep = '\\' if '\\' in file_path else '/'
            path_parts = file_path.split(sep)
            if len(path_parts) < 2:
                continue

            system_folder = path_parts[0]
            if system_folder != ra_system:
                continue

            filename = path_parts[-1]
            # Derive title: middle folder if 3 parts, else strip extension
            if len(path_parts) == 3:
                game_title = path_parts[1]
            else:
                game_title = os.path.splitext(filename)[0]

            url = _make_url(file_path.replace('\\', '/'))

            if url in seen_paths:
                continue
            seen_paths.add(url)

            game_files.append({
                'name': game_title,
                'type': src_type,
                'format': fmt,
                'url': url,
                'filename': filename,
                'host': HOST_NAME,
                'size': 0,
                'size_str': '',
                'source_url': BASE_URL,
                'md5': md5.upper(),
            })

        if not game_files or game_title is None:
            continue

        entries.append({
            'title': game_title,
            'platform': platform,
            'regions': source_config.get('regions', []),
            'links': game_files,
        })

    print(f'      ra_collection_v5 [{ra_system}]: {len(entries)} games')
    return entries


class RaCollectionV5Source:
    def __init__(self, manifest: SourceManifest):
        self.manifest = manifest

    def scrape(self, platform: str, config: PlatformConfig, ctx: BuildContext) -> list[dict[str, Any]]:
        ra_system = config.extras.get('ra_system')
        if not ra_system:
            print(f'Warning: ra_collection_v5 entry for {platform} missing ra_system in extras')
            return []
        return scrape(ra_system, platform, config.to_legacy_dict(), ctx.use_cached)


SOURCE = RaCollectionV5Source
