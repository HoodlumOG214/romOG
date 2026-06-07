"""
Fetch box art URLs and RA game IDs from the RetroAchievements API.

Runs as a post-pass after the main scrape pipeline. Matches entries in the
DB by normalized title and upserts boxart_url + rom_id.

RA system IDs: https://retroachievements.org/APIv1.php
"""
import os
import sqlite3
import time
import urllib.request
import urllib.parse
import json
import re

RA_API_BASE = 'https://retroachievements.org/API'
BOXART_BASE = 'https://media.retroachievements.org'

# romOG platform slug -> RA system ID
PLATFORM_TO_RA_SYSTEM = {
    'nes':   7,
    'fds':   7,   # RA lumps FDS under NES system
    'snes':  3,
    'gb':    4,
    'gbc':   6,
    'gba':   5,
    'n64':   2,
    'nds':   18,
    'dsi':   78,
    'min':   24,
    'vb':    28,
    'gc':    16,
    'wii':   38,
    'sms':   11,
    'gg':    15,
    'smd':   1,
    'scd':   9,
    '32x':   10,
    'sg1k':  33,
    'sat':   39,
    'dc':    40,
    'ps1':   12,
    'ps2':   21,
    'psp':   41,
    'a26':   25,
    'a78':   51,
    'lynx':  13,
    'jag':   17,
    'jcd':   77,
    'tg16':  8,
    'tgcd':  76,
    'pcfx':  49,
    'ngcd':  56,
    '3do':   43,
    'cv':    44,
    'intv':  45,
    'ws':    53,
    'ngp':   14,
    'vec':   46,
    'o2':    23,
    'msx':   29,
    'pc88':  47,
    'mame':  27,
    'fbneo': 27,
}


def _normalize(title: str) -> str:
    """Lowercase, strip punctuation and articles for fuzzy matching."""
    t = title.lower()
    t = re.sub(r"^(the|a|an)\s+", "", t)
    t = re.sub(r"[^a-z0-9 ]", "", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


def _fetch_game_list(ra_username: str, ra_api_key: str, system_id: int) -> list[dict]:
    params = urllib.parse.urlencode({
        'z': ra_username,
        'y': ra_api_key,
        'i': system_id,
    })
    url = f'{RA_API_BASE}/API_GetGameList.php?{params}'
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.loads(r.read())
    except Exception as e:
        print(f"      ra_metadata: failed to fetch system {system_id}: {e}")
        return []


def fetch_ra_metadata(db_path: str = 'romdb_temp.db') -> None:
    ra_username = os.environ.get('RA_USERNAME', 'TinyT')
    ra_api_key = os.environ.get('RA_API_KEY', '')
    if not ra_api_key:
        print("  ra_metadata: RA_API_KEY not set, skipping.")
        return

    con = sqlite3.connect(db_path)
    cur = con.cursor()

    # Get distinct platforms that have entries
    cur.execute("SELECT DISTINCT platform FROM entries")
    platforms = [row[0] for row in cur.fetchall()]

    updated = 0
    skipped = 0

    # Track which RA system IDs we've already fetched
    fetched_systems: dict[int, list[dict]] = {}

    for platform in platforms:
        system_id = PLATFORM_TO_RA_SYSTEM.get(platform)
        if system_id is None:
            continue

        if system_id not in fetched_systems:
            print(f"  ra_metadata: fetching RA system {system_id} for {platform}...")
            games = _fetch_game_list(ra_username, ra_api_key, system_id)
            # Build normalized title -> game dict
            fetched_systems[system_id] = {
                _normalize(g.get('Title', '')): g for g in games if g.get('Title')
            }
            time.sleep(0.5)  # be polite to RA servers

        game_map = fetched_systems[system_id]

        # Fetch all entries for this platform that are missing boxart
        cur.execute(
            "SELECT slug, title FROM entries WHERE platform = ? AND (boxart_url IS NULL OR boxart_url = '')",
            (platform,)
        )
        rows = cur.fetchall()

        for slug, title in rows:
            key = _normalize(title)
            game = game_map.get(key)
            if game is None:
                skipped += 1
                continue

            image_icon = game.get('ImageIcon', '')
            boxart_url = f"{BOXART_BASE}{image_icon}" if image_icon else None
            rom_id = str(game.get('ID', '')) or None

            cur.execute(
                "UPDATE entries SET boxart_url = COALESCE(boxart_url, ?), rom_id = COALESCE(rom_id, ?) WHERE slug = ?",
                (boxart_url, rom_id, slug)
            )
            updated += 1

    con.commit()
    con.close()
    print(f"  ra_metadata: updated {updated} entries, {skipped} unmatched.")
