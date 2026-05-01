#!/usr/bin/env python
"""
Build driver. Loads the source registry, walks db/platforms.yml, and runs
scrape → parse → insert for every (platform, source) pair.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Iterable

import yaml

from core import (
    BuildContext,
    PlatformConfig,
    Source,
    load_registry,
)
from database import db_manager
from parsers import gametdb, libretro, mame, no_intro, wii_rom_set_by_ghostware


PARSERS = {
    'no_intro': no_intro,
    'libretro': libretro,
    'gametdb': gametdb,
    'mame': mame,
    'wii_rom_set_by_ghostware': wii_rom_set_by_ghostware,
}


def get_parser(name):
    """Retrieve a parser by name."""
    return PARSERS.get(name)


def load_platforms(file_path: str | Path = 'platforms.yml') -> dict[str, list[dict]]:
    """Load the per-platform routing config."""
    with open(file_path, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{file_path} must be a mapping of platform -> list")
    return data


def _build_platform_config(entry: dict) -> tuple[str, PlatformConfig]:
    """Pull the source id and the typed config out of one platforms.yml entry."""
    extras = {
        k: v for k, v in entry.items()
        if k not in {'source', 'format', 'regions', 'urls', 'filter', 'type', 'parsers'}
    }
    config = PlatformConfig(
        format=entry['format'],
        regions=list(entry.get('regions') or []),
        urls=list(entry.get('urls') or []),
        type=entry.get('type', ''),
        parsers=dict(entry.get('parsers') or {}),
        filter=entry.get('filter'),
        extras=extras,
    )
    return entry['source'], config


def _print_source_header(index: int, source_id: str, config: PlatformConfig) -> None:
    print(f"  {index}) ", end='')
    print(f"[{config.format}] ", end='')
    if config.regions:
        print(f"[{', '.join(config.regions)}] ", end='')
    print(f"[{source_id}] ", end='')
    print(f"[{config.type}]")


def _tag_links(entries_out, source) -> tuple[int, int]:
    """Default source_id + requires_auth on every link.

    Scrapers may override either by setting them explicitly on the link
    dict (the IA scraper does this for restricted entries). Returns
    (entries_count, links_count) for source_health bookkeeping.
    """
    n_entries = 0
    n_links = 0
    for entry in entries_out:
        n_entries += 1
        for link in entry.get('links', []):
            n_links += 1
            link.setdefault('source_id', source.manifest.id)
            link.setdefault('requires_auth', int(bool(source.manifest.auth_required)))
    return n_entries, n_links


def process_platforms(
    platforms: dict[str, list[dict]],
    registry,
    ctx: BuildContext,
    source_filter: Iterable[str] | None = None,
) -> dict[str, dict[str, int]]:
    """Iterate platforms.yml, run each source/platform pair through the pipeline.

    Returns per-source aggregate counts so source_health can be recorded
    once the build is complete.
    """
    filter_set = set(source_filter) if source_filter else None
    source_stats: dict[str, dict[str, int]] = {}

    for platform, entries in platforms.items():
        if filter_set is not None:
            entries = [e for e in entries if e.get('source') in filter_set]
            if not entries:
                continue

        print(f"\n{platform}:")
        for i, entry in enumerate(entries, start=1):
            source_id, config = _build_platform_config(entry)
            _print_source_header(i, source_id, config)

            source = registry.get(source_id)
            if source is None:
                print(f"Source '{source_id}' not found in registry.")
                sys.exit(1)

            entries_out = source.scrape(platform, config, ctx)

            for parser_name, parser_flags in config.parsers.items():
                parser = get_parser(parser_name)
                if not parser:
                    print(f"Parser '{parser_name}' not found.")
                    sys.exit(1)
                entries_out = parser.parse(entries_out, parser_flags)

            entries_out = list(entries_out)
            ne, nl = _tag_links(entries_out, source)
            stats = source_stats.setdefault(source_id, {'entries': 0, 'links': 0})
            stats['entries'] += ne
            stats['links'] += nl

            for entry_out in entries_out:
                db_manager.insert_entry(entry_out)

    return source_stats


def make(
    use_cached: bool = False,
    platforms_file: str | Path = 'platforms.yml',
    source_filter: Iterable[str] | None = None,
) -> None:
    """Initialize the database, run the pipeline, finalize."""
    db_root = Path(__file__).resolve().parent
    registry = load_registry(db_root)
    platforms = load_platforms(platforms_file)
    db_manager.init_database()

    # Up-front so source_health always has a referent even for skipped sources.
    for manifest in registry.manifests.values():
        db_manager.register_source(manifest)

    if source_filter:
        print(f"Filtering to sources: {', '.join(source_filter)}")

    ctx = BuildContext(use_cached=use_cached)
    source_stats = process_platforms(platforms, registry, ctx, source_filter)

    for source_id in registry.ids():
        stats = source_stats.get(source_id)
        if stats is None:
            db_manager.record_source_health(
                source_id,
                status='unknown',
                reason='not run in this build',
            )
        else:
            db_manager.record_source_health(
                source_id,
                status='ok',
                entry_count=stats['entries'],
                link_count=stats['links'],
            )

    db_manager.close_database()
    print("Database created successfully.")


def _parse_args(argv: list[str]) -> dict:
    args = argv[1:] if len(argv) > 1 else []
    out = {
        'use_cached': '--use-cached' in args,
        'platforms_file': 'platforms.yml',
        'source_filter': None,
    }
    for i, arg in enumerate(args):
        if arg == '--platforms' and i + 1 < len(args):
            out['platforms_file'] = args[i + 1]
        elif arg in ('--sources', '--scrapers') and i + 1 < len(args):
            out['source_filter'] = [s.strip() for s in args[i + 1].split(',')]
    return out


if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.realpath(__file__)))
    opts = _parse_args(sys.argv)
    make(
        use_cached=opts['use_cached'],
        platforms_file=opts['platforms_file'],
        source_filter=opts['source_filter'],
    )
