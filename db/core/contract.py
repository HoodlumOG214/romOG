"""
The contract every source plugin implements.

A "source" is a single upstream that the build pipeline scrapes for ROM links.
Each source is a self-contained folder under db/sources/<source_id>/ with:

    source.yml   — static manifest (id, name, kind, capabilities, ...)
    __init__.py  — exposes a `SOURCE` symbol pointing at the Source impl
    scraper.py   — the implementation

The registry (db/core/registry.py) walks db/sources/, loads each manifest,
imports the package, and produces a usable {id: Source} map for make.py.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol, runtime_checkable


@dataclass(frozen=True)
class SourceManifest:
    """Static description of a source. Parsed from source.yml.

    `raw` holds the full parsed YAML so the manifest can be serialized into
    the catalog DB's sources.manifest_json column without information loss.
    """

    id: str
    name: str
    kind: str  # 'catalog' | 'host' | 'hybrid'
    homepage: str | None = None
    auth_required: bool = False
    priority: int = 0
    capabilities: tuple[str, ...] = ()
    platforms: tuple[str, ...] = ()
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass
class PlatformConfig:
    """Per-platform configuration for a single source.

    This is what each entry under a platform in platforms.yml turns into.
    Mirrors the legacy sources.json per-entry shape minus the `scraper` key
    (which is now the plugin folder name, not a value carried in config).
    """

    format: str
    regions: list[str]
    urls: list[str]
    type: str
    parsers: dict[str, dict]
    filter: str | None = None
    extras: dict[str, Any] = field(default_factory=dict)

    def to_legacy_dict(self) -> dict[str, Any]:
        """Render as the dict shape that legacy scraper functions expect.

        Lets Phase 1 wrap existing scraper modules without rewriting their
        internals. To be removed once all plugins consume PlatformConfig
        directly.
        """
        return {
            "format": self.format,
            "regions": list(self.regions),
            "urls": list(self.urls),
            "type": self.type,
            "parsers": dict(self.parsers),
            "filter": self.filter or "",
            **self.extras,
        }


@dataclass
class BuildContext:
    """Shared state for a single build invocation.

    Kept intentionally small. Add fields here when something *every* source
    needs (e.g., a shared HTTP session). One-off needs go in source code.
    """

    use_cached: bool = False


@runtime_checkable
class Source(Protocol):
    """Plugin contract.

    Implementations live in db/sources/<id>/scraper.py and are exposed via
    db/sources/<id>/__init__.py as a module-level `SOURCE` instance.
    """

    manifest: SourceManifest

    def scrape(
        self,
        platform: str,
        config: PlatformConfig,
        ctx: BuildContext,
    ) -> list[dict]:
        """Return entry dicts for this source on this platform.

        Entry shape (Phase 1, matches existing pipeline):
            {
                'title': str,
                'platform': str,
                'regions': list[str],
                'links': [
                    {
                        'name': str, 'type': str, 'format': str,
                        'url': str, 'filename': str, 'host': str,
                        'size': int, 'size_str': str, 'source_url': str,
                    },
                    ...
                ],
                # optional:
                'rom_id': str,
                'boxart_url': str,
            }
        """
        ...
