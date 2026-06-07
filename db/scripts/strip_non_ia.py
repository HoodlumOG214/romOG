"""Remove all non-internet_archive source entries from platforms.yml."""
import yaml
from pathlib import Path

p = Path('platforms.yml')
data = yaml.safe_load(p.read_text())

filtered = {}
for platform, entries in data.items():
    ia_entries = [e for e in entries if e.get('source') == 'internet_archive']
    if ia_entries:
        filtered[platform] = ia_entries

p.write_text(yaml.dump(filtered, default_flow_style=False, sort_keys=False, allow_unicode=True))
print(f"Kept {sum(len(v) for v in filtered.values())} IA entries across {len(filtered)} platforms")
print("Platforms retained:", list(filtered.keys()))
