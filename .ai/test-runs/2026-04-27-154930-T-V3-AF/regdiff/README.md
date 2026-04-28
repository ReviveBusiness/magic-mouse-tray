# Registry diff workspace

Side-by-side comparison of the v3 mouse registry state across three time periods:

- `2025-11-24` — backup before v3 mouse was paired (paired 2026-03-18)
- `2026-04-03` — backup during the Magic Utilities era (Magic Utilities bound to v3 from 2026-03-18 to 2026-04-17)
- `2026-04-27` — current pre-cleanup snapshot (applewirelessmouse era)
- `current` — live registry state from devmgr-dump

Files in this dir capture extracted sections (BTHENUM\...PID&0323..., applewirelessmouse service, MagicMouse service, DeviceContainers\{fbdb1973-...}) per period, plus a side-by-side diff.
