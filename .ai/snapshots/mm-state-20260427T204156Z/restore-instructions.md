# Restore from snapshot mm-state-20260427T204156Z

This snapshot was taken before a state-mutating operation. To restore:

1. Compare current state to this snapshot using ./scripts/mm-snapshot-state.sh
   to take a fresh snapshot, then `diff` the two snap_dirs.

2. To restore LowerFilters from this snapshot, read `registry.txt`, find the
   LowerFilters line, and run mm-state-flip.ps1 with the matching mode.

3. To uninstall a driver package added since this snapshot:
   pnputil /enum-drivers (compare to driver-packages.txt)
   pnputil /delete-driver <oemN.inf> /uninstall /force

4. If the BTHENUM device is in a confused state, the safest reset is a full
   unpair + repair via Bluetooth Settings.

Captured at: 2026-04-27T20:41:59Z
