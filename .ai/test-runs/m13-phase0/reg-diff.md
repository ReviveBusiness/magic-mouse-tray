# Reg-export diff verification

- pre:  `/mnt/d/Users/Lesley/Documents/Backups/2026-04-27-142015-pre-cleanup.reg`
- post: `/mnt/d/Users/Lesley/Documents/Backups/2026-04-27-144619-post-cleanup-v2.reg`
- captured: 2026-04-27T14:57:31-0600
- filter: `MagicMouse|RAWPDO|0323|applewirelessmouse|LowerFilters|UpperFilters|BTHPORT|HidBth`

## Sections removed (filtered)

- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\DeviceClasses\{fae1ef32-137e-485e-8d89-95d0d3bd8479}\##?#{7D55502A-2C87-441F-9993-0761990E0C7A}#MagicMouseRawPdo#8&4fb45d0&0&0323-2-D0C050CC8C4D#{fae1ef32-137e-485e-8d89-95d0d3bd8479}]
- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\DeviceClasses\{fae1ef32-137e-485e-8d89-95d0d3bd8479}\##?#{7D55502A-2C87-441F-9993-0761990E0C7A}#MagicMouseRawPdo#8&4fb45d0&0&0323-2-D0C050CC8C4D#{fae1ef32-137e-485e-8d89-95d0d3bd8479}\#]
- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo]
- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D]
- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D\Device Parameters]
- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D\Device Parameters\WDF]
- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver]
- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver\Parameters]
- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver\Parameters\Wdf]
- [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver\Enum]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceClasses\{fae1ef32-137e-485e-8d89-95d0d3bd8479}\##?#{7D55502A-2C87-441F-9993-0761990E0C7A}#MagicMouseRawPdo#8&4fb45d0&0&0323-2-D0C050CC8C4D#{fae1ef32-137e-485e-8d89-95d0d3bd8479}]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceClasses\{fae1ef32-137e-485e-8d89-95d0d3bd8479}\##?#{7D55502A-2C87-441F-9993-0761990E0C7A}#MagicMouseRawPdo#8&4fb45d0&0&0323-2-D0C050CC8C4D#{fae1ef32-137e-485e-8d89-95d0d3bd8479}\#]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D\Device Parameters]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D\Device Parameters\WDF]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Parameters]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Parameters\Wdf]
- [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Enum]

## Sections added (filtered)

_(none)_

## Value-level changes (filtered, hex decoded inline)

```
@@ -47680,5 +47679,0 @@
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\DeviceClasses\{fae1ef32-137e-485e-8d89-95d0d3bd8479}\##?#{7D55502A-2C87-441F-9993-0761990E0C7A}#MagicMouseRawPdo#8&4fb45d0&0&0323-2-D0C050CC8C4D#{fae1ef32-137e-485e-8d89-95d0d3bd8479}]
-"DeviceInstance"="{7D55502A-2C87-441F-9993-0761990E0C7A}\\MagicMouseRawPdo\\8&4fb45d0&0&0323-2-D0C050CC8C4D"
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\DeviceClasses\{fae1ef32-137e-485e-8d89-95d0d3bd8479}\##?#{7D55502A-2C87-441F-9993-0761990E0C7A}#MagicMouseRawPdo#8&4fb45d0&0&0323-2-D0C050CC8C4D#{fae1ef32-137e-485e-8d89-95d0d3bd8479}\#]
@@ -48010 +48004,0 @@
-"{7D55502A-2C87-441F-9993-0761990E0C7A}\\MagicMouseRawPdo\\8&4fb45d0&0&0323-2-D0C050CC8C4D"=hex(0):
@@ -157897,0 +157892 @@
@@ -178041,2 +178035,0 @@
-"LowerFilters"=hex(7)  # decoded utf-16-le: 'MagicMouse'
@@ -178963,17 +178955,0 @@
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo]
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D]
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D\Device Parameters]
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D\Device Parameters\WDF]
@@ -197521,25 +197496,0 @@
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver]
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver\Parameters]
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver\Parameters\Wdf]
-[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver\Enum]
-"0"="BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\\9&73b8b28&0&D0C050CC8C4D_C00000000"
@@ -220271,3 +220222,3 @@
@@ -220276,2 +220227,2 @@
@@ -346241 +346192 @@
@@ -346255 +346206 @@
@@ -346263,2 +346214,2 @@
@@ -346269,2 +346220,2 @@
@@ -346286,2 +346237,2 @@
@@ -346289 +346240 @@
@@ -346292,5 +346243,5 @@
@@ -346299 +346250 @@
@@ -346302,6 +346253,6 @@
@@ -346314 +346265 @@
@@ -346319,526 +346270,527 @@
@@ -395864,5 +395815,0 @@
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceClasses\{fae1ef32-137e-485e-8d89-95d0d3bd8479}\##?#{7D55502A-2C87-441F-9993-0761990E0C7A}#MagicMouseRawPdo#8&4fb45d0&0&0323-2-D0C050CC8C4D#{fae1ef32-137e-485e-8d89-95d0d3bd8479}]
-"DeviceInstance"="{7D55502A-2C87-441F-9993-0761990E0C7A}\\MagicMouseRawPdo\\8&4fb45d0&0&0323-2-D0C050CC8C4D"
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceClasses\{fae1ef32-137e-485e-8d89-95d0d3bd8479}\##?#{7D55502A-2C87-441F-9993-0761990E0C7A}#MagicMouseRawPdo#8&4fb45d0&0&0323-2-D0C050CC8C4D#{fae1ef32-137e-485e-8d89-95d0d3bd8479}\#]
@@ -396194 +396140,0 @@
-"{7D55502A-2C87-441F-9993-0761990E0C7A}\\MagicMouseRawPdo\\8&4fb45d0&0&0323-2-D0C050CC8C4D"=hex(0):
@@ -506081,0 +506028 @@
@@ -526225,2 +526171,0 @@
-"LowerFilters"=hex(7)  # decoded utf-16-le: 'MagicMouse'
@@ -527147,17 +527091,0 @@
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo]
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D]
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D\Device Parameters]
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D\Device Parameters\WDF]
@@ -545705,25 +545632,0 @@
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver]
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Parameters]
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Parameters\Wdf]
-[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Enum]
-"0"="BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\\9&73b8b28&0&D0C050CC8C4D_C00000000"
@@ -568455,3 +568358,3 @@
@@ -568460,2 +568363,2 @@
```

## Diff totals (full, unfiltered — kernel/timestamp noise included)

- sections removed: 22
- sections added: 0
- value-level diff lines: 1261
