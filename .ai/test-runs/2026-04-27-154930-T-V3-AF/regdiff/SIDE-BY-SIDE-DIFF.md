# Registry side-by-side diff — Apple peripherals

| | 2025-11-24 (pre-v3-pair) | 2026-04-03 (Magic Utilities era) | 2026-04-27 (applewirelessmouse era) |
|---|---|---|---|
| Total v3-related blocks | 0 | 16 | 22 |
| Total v1-related blocks | 10 | 28 | 0 |
| Total kbd-related blocks | 22 | 22 | 22 |
| applewirelessmouse Service | no | no | no |
| MagicMouse Service | no | no | no |


## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\DeviceContainers\{fbdb1973-434c-5160-a997-ee1429168abe}`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\DeviceContainers\{fbdb1973-434c-5160-a997-ee1429168abe}\BaseContainers`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\DeviceContainers\{fbdb1973-434c-5160-a997-ee1429168abe}\BaseContainers\{fbdb1973-434c-5160-a997-ee1429168abe}`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `BTHENUM\\Dev_D0C050CC8C4D\\9&73b8b28&0&BluetoothDevice_D0C050CC8C4D` | — | `hex(0):` | `hex(0):` |
| `BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\\9&73b8b28&0&D0C050CC8C4D_C00000000` | — | `hex(0):` | `hex(0):` |
| `BTHENUM\\{00001200-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\\9&73b8b28&0&D0C050CC8C4D_C00000000` | — | `hex(0):` | `hex(0):` |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\\a&31e5d054&2&0000` | — | `hex(0):` | — |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\\a&31e5d054&b&0000` | — | — | `hex(0):` |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\\a&31e5d054&2&0001` | — | `hex(0):` | — |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\\a&31e5d054&b&0001` | — | — | `hex(0):` |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\\a&31e5d054&b&0000` | — | — | `hex(0):` |
| `{7D55502A-2C87-441F-9993-0761990E0C7A}\\MagicMouseRawPdo\\a&31e5d054&2&0323-1-D0C050CC8C4D` | — | `hex(0):` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\Dev_04F13EEEDE10`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\Dev_04F13EEEDE10\9&73b8b28&0&BluetoothDevice_04F13EEEDE10`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Capabilities` | `dword:000000c4` | `dword:000000c4` | — |
| `ClassGUID` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | — |
| `CompatibleIDs` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | — |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | — |
| `ContainerID` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | — |
| `Driver` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0004"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0004"` | — |
| `FriendlyName` | `"Lesley’s Mouse"` | `"Lesley’s Mouse"` | — |
| `HardwareID` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | — |
| `Mfg` | `"@bth.inf,%microsoft%;Microsoft"` | `"@bth.inf,%microsoft%;Microsoft"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\Dev_04F13EEEDE10\9&73b8b28&0&BluetoothDevice_04F13EEEDE10\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Bluetooth_UniqueID` | `"{00000000-0000-0000-0000-000000000000}#04F13EE...` | `"{00000000-0000-0000-0000-000000000000}#04F13EE...` | — |
| `ConnectionCount` | `dword:00000000` | `dword:00000000` | — |
| `LowerFilters` | — | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\Dev_D0C050CC8C4D`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\Dev_D0C050CC8C4D\9&73b8b28&0&BluetoothDevice_D0C050CC8C4D`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Capabilities` | — | `dword:000000c4` | `dword:000000c4` |
| `ClassGUID` | — | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` |
| `CompatibleIDs` | — | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `ConfigFlags` | — | `dword:00000000` | `dword:00000000` |
| `ContainerID` | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` |
| `Driver` | — | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0014"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0004"` |
| `FriendlyName` | — | `"Magic Mouse"` | `"Magic Mouse"` |
| `HardwareID` | — | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `Mfg` | — | `"@bth.inf,%microsoft%;Microsoft"` | `"@bth.inf,%microsoft%;Microsoft"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\Dev_D0C050CC8C4D\9&73b8b28&0&BluetoothDevice_D0C050CC8C4D\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Bluetooth_UniqueID` | — | `"{00000000-0000-0000-0000-000000000000}#D0C050C...` | `"{00000000-0000-0000-0000-000000000000}#D0C050C...` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\Dev_E806884B0741`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\Dev_E806884B0741\9&73b8b28&0&BluetoothDevice_E806884B0741`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Capabilities` | `dword:000000c4` | `dword:000000c4` | `dword:000000c4` |
| `ClassGUID` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` |
| `CompatibleIDs` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` |
| `Driver` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0005"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0005"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0005"` |
| `FriendlyName` | `"Trevor’s Keyboard"` | `"Trevor’s Keyboard"` | `"Trevor’s Keyboard"` |
| `HardwareID` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `Mfg` | `"@bth.inf,%microsoft%;Microsoft"` | `"@bth.inf,%microsoft%;Microsoft"` | `"@bth.inf,%microsoft%;Microsoft"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\Dev_E806884B0741\9&73b8b28&0&BluetoothDevice_E806884B0741\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Bluetooth_UniqueID` | `"{00000000-0000-0000-0000-000000000000}#E806884...` | `"{00000000-0000-0000-0000-000000000000}#E806884...` | `"{00000000-0000-0000-0000-000000000000}#E806884...` |
| `ConnectionCount` | — | `dword:00000000` | `dword:00000000` |
| `LowerFilters` | — | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Capabilities` | — | `dword:00000080` | `dword:00000080` |
| `ClassGUID` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | — | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `ConfigFlags` | — | `dword:00000000` | `dword:00000000` |
| `ContainerID` | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | `"@oem53.inf,%mm3.descbth%;Magic Mouse 2024 - Bl...` | `"@oem0.inf,%applewirelessmouse.devicedesc%;Appl...` |
| `Driver` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0014"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0005"` |
| `HardwareID` | — | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `LowerFilters` | — | `hex(7):4d,00,61,00,67,00,69,00,63,00,4d,00,6f,0...` | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` |
| `Mfg` | — | `"@oem53.inf,%manufacturer%;Apple Inc."` | `"@oem0.inf,%mfgname%;Apple Inc."` |
| `ParentIdPrefix` | — | `"a&31e5d054&2"` | `"a&31e5d054&b"` |
| `Service` | — | `"HidBth"` | `"HidBth"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `AllowIdleIrpInD3` | — | `dword:00000001` | `dword:00000001` |
| `BluetoothAddress` | — | `hex(0):4d,8c,cc,50,c0,d0,00,00` | `hex(0):4d,8c,cc,50,c0,d0,00,00` |
| `Bluetooth_UniqueID` | — | `"{00001124-0000-1000-8000-00805f9b34fb}#D0C050C...` | `"{00001124-0000-1000-8000-00805f9b34fb}#D0C050C...` |
| `ConnectionAuthenticated` | — | `dword:00000001` | `dword:00000001` |
| `ConnectionCount` | — | — | `dword:00000004` |
| `DeviceResetNotificationEnabled` | — | `dword:00000001` | `dword:00000001` |
| `EnhancedPowerManagementEnabled` | — | `dword:00000001` | `dword:00000001` |
| `LegacyTouchScaling` | — | `dword:00000000` | `dword:00000000` |
| `SelectiveSuspendEnabled` | — | `hex:00` | `hex:00` |
| `SelectiveSuspendOn` | — | `dword:00000000` | — |
| `VirtuallyCabled` | — | `dword:00000001` | `dword:00000001` |
| `WriteReportExSupported` | — | `dword:00000001` | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239\9&73b8b28&0&E806884B0741_C00000000`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Capabilities` | `dword:00000080` | `dword:00000080` | `dword:00000080` |
| `ClassGUID` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@hidbth.inf,%bthenum\\{00001124-0000-1000-8000...` | `"@hidbth.inf,%bthenum\\{00001124-0000-1000-8000...` | `"@hidbth.inf,%bthenum\\{00001124-0000-1000-8000...` |
| `Driver` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0003"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0003"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0003"` |
| `HardwareID` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `Mfg` | `"@hidbth.inf,%msft%;Microsoft"` | `"@hidbth.inf,%msft%;Microsoft"` | `"@hidbth.inf,%msft%;Microsoft"` |
| `ParentIdPrefix` | `"a&eaf9d13&2"` | `"a&eaf9d13&2"` | `"a&eaf9d13&2"` |
| `Service` | `"HidBth"` | `"HidBth"` | `"HidBth"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239\9&73b8b28&0&E806884B0741_C00000000\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `BluetoothAddress` | `hex(0):41,07,4b,88,06,e8,00,00` | `hex(0):41,07,4b,88,06,e8,00,00` | `hex(0):41,07,4b,88,06,e8,00,00` |
| `Bluetooth_UniqueID` | `"{00001124-0000-1000-8000-00805f9b34fb}#E806884...` | `"{00001124-0000-1000-8000-00805f9b34fb}#E806884...` | `"{00001124-0000-1000-8000-00805f9b34fb}#E806884...` |
| `ConnectionAuthenticated` | `dword:00000001` | `dword:00000001` | `dword:00000001` |
| `ConnectionCount` | — | `dword:00000004` | `dword:0000001a` |
| `LegacyTouchScaling` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `LowerFilters` | — | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` |
| `RetainWWIrpWhenDeviceAbsent` | `dword:00000001` | `dword:00000001` | `dword:00000001` |
| `VirtuallyCabled` | `dword:00000001` | `dword:00000001` | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d\9&73b8b28&0&04F13EEEDE10_C00000000`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Capabilities` | `dword:00000080` | `dword:00000080` | — |
| `ClassGUID` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | — |
| `CompatibleIDs` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | — |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | — |
| `ContainerID` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | `"@oem10.inf,%applewirelessmouse.devicedesc%;App...` | `"@oem53.inf,%mm1.descbth%;Magic Mouse 2009 - Bl...` | — |
| `Driver` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0005"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0005"` | — |
| `HardwareID` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | — |
| `LowerFilters` | `hex(7):61,00,70,00,70,00,6c,00,65,00,62,00,6d,0...` | `hex(7):4d,00,61,00,67,00,69,00,63,00,4d,00,6f,0...` | — |
| `Mfg` | `"@oem10.inf,%mfgname%;Apple Inc."` | `"@oem53.inf,%manufacturer%;Apple Inc."` | — |
| `ParentIdPrefix` | `"a&137e1bf2&1"` | `"a&137e1bf2&1"` | — |
| `Service` | `"HidBth"` | `"HidBth"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d\9&73b8b28&0&04F13EEEDE10_C00000000\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `AllowIdleIrpInD3` | `dword:00000001` | `dword:00000001` | — |
| `BluetoothAddress` | `hex(0):10,de,ee,3e,f1,04,00,00` | `hex(0):10,de,ee,3e,f1,04,00,00` | — |
| `Bluetooth_UniqueID` | `"{00001124-0000-1000-8000-00805f9b34fb}#04F13EE...` | `"{00001124-0000-1000-8000-00805f9b34fb}#04F13EE...` | — |
| `ConnectionAuthenticated` | `dword:00000001` | `dword:00000001` | — |
| `ConnectionCount` | `dword:000000aa` | `dword:000000c8` | — |
| `DeviceResetNotificationEnabled` | `dword:00000001` | `dword:00000001` | — |
| `EnhancedPowerManagementEnabled` | `dword:00000001` | `dword:00000001` | — |
| `LegacyTouchScaling` | `dword:00000000` | `dword:00000000` | — |
| `LowerFilters` | — | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` | — |
| `SelectiveSuspendEnabled` | `hex:00` | `hex:00` | — |
| `SelectiveSuspendOn` | — | `dword:00000000` | — |
| `VirtuallyCabled` | `dword:00000001` | `dword:00000001` | — |
| `WriteReportExSupported` | `dword:00000001` | `dword:00000001` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\a&31e5d054&2&0000`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000001` | — |
| `Capabilities` | — | `dword:000000a0` | — |
| `ClassGUID` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` | — |
| `DeviceDesc` | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | — |
| `Driver` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0003"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@msmouse.inf,%msmfg%;Microsoft"` | — |
| `Service` | — | `"mouhid"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\a&31e5d054&2&0000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `FlipFlopHScroll` | — | `dword:00000000` | — |
| `FlipFlopWheel` | — | `dword:00000000` | — |
| `ForceAbsolute` | — | `dword:00000000` | — |
| `HScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `HScrollPageOverride` | — | `dword:00000000` | — |
| `HScrollUsageOverride` | — | `dword:00000000` | — |
| `VScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `VScrollPageOverride` | — | `dword:00000000` | — |
| `VScrollUsageOverride` | — | `dword:00000000` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\a&31e5d054&b&0000`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `Address` | — | — | `dword:00000001` |
| `Capabilities` | — | — | `dword:000000a0` |
| `ClassGUID` | — | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` |
| `CompatibleIDs` | — | — | `hex(7):00,00,00,00` |
| `ConfigFlags` | — | — | `dword:00000000` |
| `ContainerID` | — | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` |
| `Driver` | — | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0005"` |
| `HardwareID` | — | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | — | — | `"@msmouse.inf,%msmfg%;Microsoft"` |
| `Service` | — | — | `"mouhid"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\a&31e5d054&b&0000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `FlipFlopHScroll` | — | — | `dword:00000000` |
| `FlipFlopWheel` | — | — | `dword:00000000` |
| `ForceAbsolute` | — | — | `dword:00000000` |
| `HScrollHighResolutionDisable` | — | — | `dword:00000000` |
| `HScrollPageOverride` | — | — | `dword:00000000` |
| `HScrollUsageOverride` | — | — | `dword:00000000` |
| `VScrollHighResolutionDisable` | — | — | `dword:00000000` |
| `VScrollPageOverride` | — | — | `dword:00000000` |
| `VScrollUsageOverride` | — | — | `dword:00000000` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\a&31e5d054&2&0001`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000002` | — |
| `Capabilities` | — | `dword:000000e0` | — |
| `ClassGUID` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` | — |
| `DeviceDesc` | — | `"@input.inf,%hid_device_vendor_defined_range%;H...` | — |
| `Driver` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0015"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@input.inf,%stdmfg%;(Standard system devices)"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\a&31e5d054&2&0001\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\a&31e5d054&b&0001`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `Address` | — | — | `dword:00000002` |
| `Capabilities` | — | — | `dword:000000e0` |
| `ClassGUID` | — | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | — | — | `hex(7):00,00,00,00` |
| `ConfigFlags` | — | — | `dword:00000000` |
| `ContainerID` | — | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | — | `"@input.inf,%hid_device_vendor_defined_range%;H...` |
| `Driver` | — | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0015"` |
| `HardwareID` | — | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | — | — | `"@input.inf,%stdmfg%;(Standard system devices)"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\a&31e5d054&b&0001\Device Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\a&31e5d054&b&0000`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `Address` | — | — | `dword:00000001` |
| `Capabilities` | — | — | `dword:000000a0` |
| `ClassGUID` | — | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` |
| `CompatibleIDs` | — | — | `hex(7):00,00,00,00` |
| `ConfigFlags` | — | — | `dword:00000000` |
| `ContainerID` | — | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` |
| `Driver` | — | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0003"` |
| `HardwareID` | — | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | — | — | `"@msmouse.inf,%msmfg%;Microsoft"` |
| `Service` | — | — | `"mouhid"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\a&31e5d054&b&0000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `FlipFlopHScroll` | — | — | `dword:00000000` |
| `FlipFlopWheel` | — | — | `dword:00000000` |
| `ForceAbsolute` | — | — | `dword:00000000` |
| `HScrollHighResolutionDisable` | — | — | `dword:00000000` |
| `HScrollPageOverride` | — | — | `dword:00000000` |
| `HScrollUsageOverride` | — | — | `dword:00000000` |
| `VScrollHighResolutionDisable` | — | — | `dword:00000000` |
| `VScrollPageOverride` | — | — | `dword:00000000` |
| `VScrollUsageOverride` | — | — | `dword:00000000` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col01`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col01\a&eaf9d13&2&0000`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Address` | `dword:00000001` | `dword:00000001` | `dword:00000001` |
| `Capabilities` | `dword:000000a0` | `dword:000000a0` | `dword:000000a0` |
| `ClassGUID` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}"` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}"` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}"` |
| `CompatibleIDs` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@keyboard.inf,%hid.keyboarddevice%;HID Keyboar...` | `"@keyboard.inf,%hid.keyboarddevice%;HID Keyboar...` | `"@keyboard.inf,%hid.keyboarddevice%;HID Keyboar...` |
| `Driver` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}\\0000"` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}\\0000"` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}\\0000"` |
| `HardwareID` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | `"@keyboard.inf,%std-keyboards%;(Standard keyboa...` | `"@keyboard.inf,%std-keyboards%;(Standard keyboa...` | `"@keyboard.inf,%std-keyboards%;(Standard keyboa...` |
| `Service` | `"kbdhid"` | `"kbdhid"` | `"kbdhid"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col01\a&eaf9d13&2&0000\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col02`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col02\a&eaf9d13&2&0001`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Address` | `dword:00000002` | `dword:00000002` | `dword:00000002` |
| `Capabilities` | `dword:000000e0` | `dword:000000e0` | `dword:000000e0` |
| `ClassGUID` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` |
| `Driver` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0004"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0004"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0004"` |
| `HardwareID` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col02\a&eaf9d13&2&0001\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col03`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col03\a&eaf9d13&2&0002`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Address` | `dword:00000003` | `dword:00000003` | `dword:00000003` |
| `Capabilities` | `dword:000000e0` | `dword:000000e0` | `dword:000000e0` |
| `ClassGUID` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` |
| `Driver` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0013"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0013"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0013"` |
| `HardwareID` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col03\a&eaf9d13&2&0002\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col01`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col01\a&137e1bf2&1&0000`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000001` | — |
| `Capabilities` | — | `dword:000000a0` | — |
| `ClassGUID` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | — |
| `Driver` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0005"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@msmouse.inf,%msmfg%;Microsoft"` | — |
| `Service` | — | `"mouhid"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col01\a&137e1bf2&1&0000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `FlipFlopHScroll` | — | `dword:00000000` | — |
| `FlipFlopWheel` | — | `dword:00000000` | — |
| `ForceAbsolute` | — | `dword:00000000` | — |
| `HScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `HScrollPageOverride` | — | `dword:00000000` | — |
| `HScrollUsageOverride` | — | `dword:00000000` | — |
| `VScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `VScrollPageOverride` | — | `dword:00000000` | — |
| `VScrollUsageOverride` | — | `dword:00000000` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col02`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col02\a&137e1bf2&1&0001`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000002` | — |
| `Capabilities` | — | `dword:000000a0` | — |
| `ClassGUID` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | — |
| `Driver` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0006"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@msmouse.inf,%msmfg%;Microsoft"` | — |
| `Service` | — | `"mouhid"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col02\a&137e1bf2&1&0001\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `FlipFlopHScroll` | — | `dword:00000000` | — |
| `FlipFlopWheel` | — | `dword:00000000` | — |
| `ForceAbsolute` | — | `dword:00000000` | — |
| `HScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `HScrollPageOverride` | — | `dword:00000000` | — |
| `HScrollUsageOverride` | — | `dword:00000000` | — |
| `VScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `VScrollPageOverride` | — | `dword:00000000` | — |
| `VScrollUsageOverride` | — | `dword:00000000` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col03`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col03\a&137e1bf2&1&0002`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000003` | — |
| `Capabilities` | — | `dword:000000e0` | — |
| `ClassGUID` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | — | `"@input.inf,%hid_device_vendor_defined_range%;H...` | — |
| `Driver` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0016"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@input.inf,%stdmfg%;(Standard system devices)"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col03\a&137e1bf2&1&0002\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d\a&137e1bf2&1&0000`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | `dword:00000001` | `dword:00000001` | — |
| `Capabilities` | `dword:000000a0` | `dword:000000a0` | — |
| `ClassGUID` | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | — |
| `CompatibleIDs` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | — |
| `ContainerID` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | — |
| `Driver` | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0000"` | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0000"` | — |
| `HardwareID` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | `"@msmouse.inf,%msmfg%;Microsoft"` | `"@msmouse.inf,%msmfg%;Microsoft"` | — |
| `Service` | `"mouhid"` | `"mouhid"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d\a&137e1bf2&1&0000\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `FlipFlopHScroll` | `dword:00000000` | `dword:00000000` | — |
| `FlipFlopWheel` | `dword:00000000` | `dword:00000000` | — |
| `ForceAbsolute` | `dword:00000000` | `dword:00000000` | — |
| `HScrollHighResolutionDisable` | `dword:00000000` | `dword:00000000` | — |
| `HScrollPageOverride` | `dword:00000000` | `dword:00000000` | — |
| `HScrollUsageOverride` | `dword:00000000` | `dword:00000000` | — |
| `VScrollHighResolutionDisable` | `dword:00000000` | `dword:00000000` | — |
| `VScrollPageOverride` | `dword:00000000` | `dword:00000000` | — |
| `VScrollUsageOverride` | `dword:00000000` | `dword:00000000` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\applebmt`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `DisplayName` | `"@oem10.inf,%AppleWirelessMouse.SvcDesc%;Apple ...` | `"@oem10.inf,%AppleWirelessMouse.SvcDesc%;Apple ...` | — |
| `ErrorControl` | `dword:00000000` | `dword:00000000` | — |
| `ImagePath` | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` | — |
| `Owners` | `hex(7):6f,00,65,00,6d,00,31,00,30,00,2e,00,69,0...` | `hex(7):6f,00,65,00,6d,00,31,00,30,00,2e,00,69,0...` | — |
| `Start` | `dword:00000003` | `dword:00000003` | — |
| `Type` | `dword:00000001` | `dword:00000001` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\applebmt\Enum`

| Existence | 11-24: **YES** | 04-03: **no** | 04-27: **no** |
|---|---|---|---|
| `0` | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` | — | — |
| `Count` | `dword:00000001` | — | — |
| `NextInstance` | `dword:00000001` | — | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\applebmt\Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\applebmt\Parameters\Wdf`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `WdfMajorVersion` | `dword:00000001` | `dword:00000001` | — |
| `WdfMinorVersion` | `dword:00000005` | `dword:00000005` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\applewirelessmouse`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `DisplayName` | — | — | `"@oem0.inf,%AppleWirelessMouse.SvcDesc%;Apple W...` |
| `ErrorControl` | — | `dword:00000001` | `dword:00000000` |
| `Group` | — | — | `""` |
| `ImagePath` | — | `hex(2):53,00,79,00,73,00,74,00,65,00,6d,00,33,0...` | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` |
| `Owners` | — | — | `hex(7):6f,00,65,00,6d,00,30,00,2e,00,69,00,6e,0...` |
| `Start` | — | `dword:00000003` | `dword:00000003` |
| `Type` | — | `dword:00000001` | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\applewirelessmouse\Enum`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `0` | — | — | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` |
| `Count` | — | — | `dword:00000001` |
| `NextInstance` | — | — | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\applewirelessmouse\Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\applewirelessmouse\Parameters\Wdf`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `WdfMajorVersion` | — | — | `dword:00000001` |
| `WdfMinorVersion` | — | — | `dword:0000000f` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouse`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `DisplayName` | — | `"@oem53.inf,%Service.Desc%;Magic Mouse Service"` | — |
| `ErrorControl` | — | `dword:00000001` | — |
| `Group` | — | `""` | — |
| `ImagePath` | — | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` | — |
| `Owners` | — | `hex(7):6f,00,65,00,6d,00,35,00,33,00,2e,00,69,0...` | — |
| `Start` | — | `dword:00000003` | — |
| `Type` | — | `dword:00000001` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouse\Enum`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `0` | — | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` | — |
| `1` | — | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` | — |
| `Count` | — | `dword:00000002` | — |
| `NextInstance` | — | `dword:00000002` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouse\Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouse\Parameters\Wdf`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `KmdfLibraryVersion` | — | `"1.15"` | — |
| `WdfMajorVersion` | — | `dword:00000001` | — |
| `WdfMinorVersion` | — | `dword:0000000f` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `DeleteFlag` | — | — | `dword:00000001` |
| `DisplayName` | — | — | `"@oem52.inf,%ServiceDesc%;Magic Mouse Driver (s...` |
| `DriverDelete` | — | — | `dword:00000001` |
| `ErrorControl` | — | — | `dword:00000001` |
| `Group` | — | — | `""` |
| `ImagePath` | — | — | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` |
| `Start` | — | — | `dword:00000004` |
| `Type` | — | — | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver\Enum`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `0` | — | — | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` |
| `Count` | — | — | `dword:00000001` |
| `NextInstance` | — | — | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver\Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MagicMouseDriver\Parameters\Wdf`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `WdfMajorVersion` | — | — | `dword:00000001` |
| `WdfMinorVersion` | — | — | `dword:0000000f` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceContainers\{fbdb1973-434c-5160-a997-ee1429168abe}`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceContainers\{fbdb1973-434c-5160-a997-ee1429168abe}\BaseContainers`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceContainers\{fbdb1973-434c-5160-a997-ee1429168abe}\BaseContainers\{fbdb1973-434c-5160-a997-ee1429168abe}`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `BTHENUM\\Dev_D0C050CC8C4D\\9&73b8b28&0&BluetoothDevice_D0C050CC8C4D` | — | `hex(0):` | `hex(0):` |
| `BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\\9&73b8b28&0&D0C050CC8C4D_C00000000` | — | `hex(0):` | `hex(0):` |
| `BTHENUM\\{00001200-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\\9&73b8b28&0&D0C050CC8C4D_C00000000` | — | `hex(0):` | `hex(0):` |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\\a&31e5d054&2&0000` | — | `hex(0):` | — |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\\a&31e5d054&b&0000` | — | — | `hex(0):` |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\\a&31e5d054&2&0001` | — | `hex(0):` | — |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\\a&31e5d054&b&0001` | — | — | `hex(0):` |
| `HID\\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\\a&31e5d054&b&0000` | — | — | `hex(0):` |
| `{7D55502A-2C87-441F-9993-0761990E0C7A}\\MagicMouseRawPdo\\a&31e5d054&2&0323-1-D0C050CC8C4D` | — | `hex(0):` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\Dev_04F13EEEDE10`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\Dev_04F13EEEDE10\9&73b8b28&0&BluetoothDevice_04F13EEEDE10`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Capabilities` | `dword:000000c4` | `dword:000000c4` | — |
| `ClassGUID` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | — |
| `CompatibleIDs` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | — |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | — |
| `ContainerID` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | — |
| `Driver` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0004"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0004"` | — |
| `FriendlyName` | `"Lesley’s Mouse"` | `"Lesley’s Mouse"` | — |
| `HardwareID` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | — |
| `Mfg` | `"@bth.inf,%microsoft%;Microsoft"` | `"@bth.inf,%microsoft%;Microsoft"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\Dev_04F13EEEDE10\9&73b8b28&0&BluetoothDevice_04F13EEEDE10\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Bluetooth_UniqueID` | `"{00000000-0000-0000-0000-000000000000}#04F13EE...` | `"{00000000-0000-0000-0000-000000000000}#04F13EE...` | — |
| `ConnectionCount` | `dword:00000000` | `dword:00000000` | — |
| `LowerFilters` | — | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\Dev_D0C050CC8C4D`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\Dev_D0C050CC8C4D\9&73b8b28&0&BluetoothDevice_D0C050CC8C4D`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Capabilities` | — | `dword:000000c4` | `dword:000000c4` |
| `ClassGUID` | — | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` |
| `CompatibleIDs` | — | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `ConfigFlags` | — | `dword:00000000` | `dword:00000000` |
| `ContainerID` | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` |
| `Driver` | — | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0014"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0004"` |
| `FriendlyName` | — | `"Magic Mouse"` | `"Magic Mouse"` |
| `HardwareID` | — | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `Mfg` | — | `"@bth.inf,%microsoft%;Microsoft"` | `"@bth.inf,%microsoft%;Microsoft"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\Dev_D0C050CC8C4D\9&73b8b28&0&BluetoothDevice_D0C050CC8C4D\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Bluetooth_UniqueID` | — | `"{00000000-0000-0000-0000-000000000000}#D0C050C...` | `"{00000000-0000-0000-0000-000000000000}#D0C050C...` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\Dev_E806884B0741`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\Dev_E806884B0741\9&73b8b28&0&BluetoothDevice_E806884B0741`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Capabilities` | `dword:000000c4` | `dword:000000c4` | `dword:000000c4` |
| `ClassGUID` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"` |
| `CompatibleIDs` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` | `"@bth.inf,%bthenum\\generic_device%;Bluetooth D...` |
| `Driver` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0005"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0005"` | `"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\\0005"` |
| `FriendlyName` | `"Trevor’s Keyboard"` | `"Trevor’s Keyboard"` | `"Trevor’s Keyboard"` |
| `HardwareID` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `Mfg` | `"@bth.inf,%microsoft%;Microsoft"` | `"@bth.inf,%microsoft%;Microsoft"` | `"@bth.inf,%microsoft%;Microsoft"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\Dev_E806884B0741\9&73b8b28&0&BluetoothDevice_E806884B0741\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Bluetooth_UniqueID` | `"{00000000-0000-0000-0000-000000000000}#E806884...` | `"{00000000-0000-0000-0000-000000000000}#E806884...` | `"{00000000-0000-0000-0000-000000000000}#E806884...` |
| `ConnectionCount` | — | `dword:00000000` | `dword:00000000` |
| `LowerFilters` | — | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Capabilities` | — | `dword:00000080` | `dword:00000080` |
| `ClassGUID` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | — | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `ConfigFlags` | — | `dword:00000000` | `dword:00000000` |
| `ContainerID` | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | `"@oem53.inf,%mm3.descbth%;Magic Mouse 2024 - Bl...` | `"@oem0.inf,%applewirelessmouse.devicedesc%;Appl...` |
| `Driver` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0014"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0005"` |
| `HardwareID` | — | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `LowerFilters` | — | `hex(7):4d,00,61,00,67,00,69,00,63,00,4d,00,6f,0...` | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` |
| `Mfg` | — | `"@oem53.inf,%manufacturer%;Apple Inc."` | `"@oem0.inf,%mfgname%;Apple Inc."` |
| `ParentIdPrefix` | — | `"a&31e5d054&2"` | `"a&31e5d054&b"` |
| `Service` | — | `"HidBth"` | `"HidBth"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `AllowIdleIrpInD3` | — | `dword:00000001` | `dword:00000001` |
| `BluetoothAddress` | — | `hex(0):4d,8c,cc,50,c0,d0,00,00` | `hex(0):4d,8c,cc,50,c0,d0,00,00` |
| `Bluetooth_UniqueID` | — | `"{00001124-0000-1000-8000-00805f9b34fb}#D0C050C...` | `"{00001124-0000-1000-8000-00805f9b34fb}#D0C050C...` |
| `ConnectionAuthenticated` | — | `dword:00000001` | `dword:00000001` |
| `ConnectionCount` | — | — | `dword:00000004` |
| `DeviceResetNotificationEnabled` | — | `dword:00000001` | `dword:00000001` |
| `EnhancedPowerManagementEnabled` | — | `dword:00000001` | `dword:00000001` |
| `LegacyTouchScaling` | — | `dword:00000000` | `dword:00000000` |
| `SelectiveSuspendEnabled` | — | `hex:00` | `hex:00` |
| `SelectiveSuspendOn` | — | `dword:00000000` | — |
| `VirtuallyCabled` | — | `dword:00000001` | `dword:00000001` |
| `WriteReportExSupported` | — | `dword:00000001` | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239\9&73b8b28&0&E806884B0741_C00000000`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Capabilities` | `dword:00000080` | `dword:00000080` | `dword:00000080` |
| `ClassGUID` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@hidbth.inf,%bthenum\\{00001124-0000-1000-8000...` | `"@hidbth.inf,%bthenum\\{00001124-0000-1000-8000...` | `"@hidbth.inf,%bthenum\\{00001124-0000-1000-8000...` |
| `Driver` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0003"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0003"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0003"` |
| `HardwareID` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` |
| `Mfg` | `"@hidbth.inf,%msft%;Microsoft"` | `"@hidbth.inf,%msft%;Microsoft"` | `"@hidbth.inf,%msft%;Microsoft"` |
| `ParentIdPrefix` | `"a&eaf9d13&2"` | `"a&eaf9d13&2"` | `"a&eaf9d13&2"` |
| `Service` | `"HidBth"` | `"HidBth"` | `"HidBth"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239\9&73b8b28&0&E806884B0741_C00000000\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `BluetoothAddress` | `hex(0):41,07,4b,88,06,e8,00,00` | `hex(0):41,07,4b,88,06,e8,00,00` | `hex(0):41,07,4b,88,06,e8,00,00` |
| `Bluetooth_UniqueID` | `"{00001124-0000-1000-8000-00805f9b34fb}#E806884...` | `"{00001124-0000-1000-8000-00805f9b34fb}#E806884...` | `"{00001124-0000-1000-8000-00805f9b34fb}#E806884...` |
| `ConnectionAuthenticated` | `dword:00000001` | `dword:00000001` | `dword:00000001` |
| `ConnectionCount` | — | `dword:00000004` | `dword:0000001a` |
| `LegacyTouchScaling` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `LowerFilters` | — | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` |
| `RetainWWIrpWhenDeviceAbsent` | `dword:00000001` | `dword:00000001` | `dword:00000001` |
| `VirtuallyCabled` | `dword:00000001` | `dword:00000001` | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d\9&73b8b28&0&04F13EEEDE10_C00000000`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Capabilities` | `dword:00000080` | `dword:00000080` | — |
| `ClassGUID` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | — |
| `CompatibleIDs` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | — |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | — |
| `ContainerID` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | `"@oem10.inf,%applewirelessmouse.devicedesc%;App...` | `"@oem53.inf,%mm1.descbth%;Magic Mouse 2009 - Bl...` | — |
| `Driver` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0005"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0005"` | — |
| `HardwareID` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | `hex(7):42,00,54,00,48,00,45,00,4e,00,55,00,4d,0...` | — |
| `LowerFilters` | `hex(7):61,00,70,00,70,00,6c,00,65,00,62,00,6d,0...` | `hex(7):4d,00,61,00,67,00,69,00,63,00,4d,00,6f,0...` | — |
| `Mfg` | `"@oem10.inf,%mfgname%;Apple Inc."` | `"@oem53.inf,%manufacturer%;Apple Inc."` | — |
| `ParentIdPrefix` | `"a&137e1bf2&1"` | `"a&137e1bf2&1"` | — |
| `Service` | `"HidBth"` | `"HidBth"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d\9&73b8b28&0&04F13EEEDE10_C00000000\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `AllowIdleIrpInD3` | `dword:00000001` | `dword:00000001` | — |
| `BluetoothAddress` | `hex(0):10,de,ee,3e,f1,04,00,00` | `hex(0):10,de,ee,3e,f1,04,00,00` | — |
| `Bluetooth_UniqueID` | `"{00001124-0000-1000-8000-00805f9b34fb}#04F13EE...` | `"{00001124-0000-1000-8000-00805f9b34fb}#04F13EE...` | — |
| `ConnectionAuthenticated` | `dword:00000001` | `dword:00000001` | — |
| `ConnectionCount` | `dword:000000aa` | `dword:000000c8` | — |
| `DeviceResetNotificationEnabled` | `dword:00000001` | `dword:00000001` | — |
| `EnhancedPowerManagementEnabled` | `dword:00000001` | `dword:00000001` | — |
| `LegacyTouchScaling` | `dword:00000000` | `dword:00000000` | — |
| `LowerFilters` | — | `hex(7):61,00,70,00,70,00,6c,00,65,00,77,00,69,0...` | — |
| `SelectiveSuspendEnabled` | `hex:00` | `hex:00` | — |
| `SelectiveSuspendOn` | — | `dword:00000000` | — |
| `VirtuallyCabled` | `dword:00000001` | `dword:00000001` | — |
| `WriteReportExSupported` | `dword:00000001` | `dword:00000001` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\a&31e5d054&2&0000`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000001` | — |
| `Capabilities` | — | `dword:000000a0` | — |
| `ClassGUID` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` | — |
| `DeviceDesc` | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | — |
| `Driver` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0003"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@msmouse.inf,%msmfg%;Microsoft"` | — |
| `Service` | — | `"mouhid"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\a&31e5d054&2&0000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `FlipFlopHScroll` | — | `dword:00000000` | — |
| `FlipFlopWheel` | — | `dword:00000000` | — |
| `ForceAbsolute` | — | `dword:00000000` | — |
| `HScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `HScrollPageOverride` | — | `dword:00000000` | — |
| `HScrollUsageOverride` | — | `dword:00000000` | — |
| `VScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `VScrollPageOverride` | — | `dword:00000000` | — |
| `VScrollUsageOverride` | — | `dword:00000000` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\a&31e5d054&b&0000`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `Address` | — | — | `dword:00000001` |
| `Capabilities` | — | — | `dword:000000a0` |
| `ClassGUID` | — | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` |
| `CompatibleIDs` | — | — | `hex(7):00,00,00,00` |
| `ConfigFlags` | — | — | `dword:00000000` |
| `ContainerID` | — | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` |
| `Driver` | — | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0005"` |
| `HardwareID` | — | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | — | — | `"@msmouse.inf,%msmfg%;Microsoft"` |
| `Service` | — | — | `"mouhid"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col01\a&31e5d054&b&0000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `FlipFlopHScroll` | — | — | `dword:00000000` |
| `FlipFlopWheel` | — | — | `dword:00000000` |
| `ForceAbsolute` | — | — | `dword:00000000` |
| `HScrollHighResolutionDisable` | — | — | `dword:00000000` |
| `HScrollPageOverride` | — | — | `dword:00000000` |
| `HScrollUsageOverride` | — | — | `dword:00000000` |
| `VScrollHighResolutionDisable` | — | — | `dword:00000000` |
| `VScrollPageOverride` | — | — | `dword:00000000` |
| `VScrollUsageOverride` | — | — | `dword:00000000` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\a&31e5d054&2&0001`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000002` | — |
| `Capabilities` | — | `dword:000000e0` | — |
| `ClassGUID` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` | — |
| `DeviceDesc` | — | `"@input.inf,%hid_device_vendor_defined_range%;H...` | — |
| `Driver` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0015"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@input.inf,%stdmfg%;(Standard system devices)"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\a&31e5d054&2&0001\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\a&31e5d054&b&0001`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `Address` | — | — | `dword:00000002` |
| `Capabilities` | — | — | `dword:000000e0` |
| `ClassGUID` | — | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | — | — | `hex(7):00,00,00,00` |
| `ConfigFlags` | — | — | `dword:00000000` |
| `ContainerID` | — | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | — | `"@input.inf,%hid_device_vendor_defined_range%;H...` |
| `Driver` | — | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0015"` |
| `HardwareID` | — | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | — | — | `"@input.inf,%stdmfg%;(Standard system devices)"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323&Col02\a&31e5d054&b&0001\Device Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\a&31e5d054&b&0000`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `Address` | — | — | `dword:00000001` |
| `Capabilities` | — | — | `dword:000000a0` |
| `ClassGUID` | — | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` |
| `CompatibleIDs` | — | — | `hex(7):00,00,00,00` |
| `ConfigFlags` | — | — | `dword:00000000` |
| `ContainerID` | — | — | `"{fbdb1973-434c-5160-a997-ee1429168abe}"` |
| `DeviceDesc` | — | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` |
| `Driver` | — | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0003"` |
| `HardwareID` | — | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | — | — | `"@msmouse.inf,%msmfg%;Microsoft"` |
| `Service` | — | — | `"mouhid"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\a&31e5d054&b&0000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `FlipFlopHScroll` | — | — | `dword:00000000` |
| `FlipFlopWheel` | — | — | `dword:00000000` |
| `ForceAbsolute` | — | — | `dword:00000000` |
| `HScrollHighResolutionDisable` | — | — | `dword:00000000` |
| `HScrollPageOverride` | — | — | `dword:00000000` |
| `HScrollUsageOverride` | — | — | `dword:00000000` |
| `VScrollHighResolutionDisable` | — | — | `dword:00000000` |
| `VScrollPageOverride` | — | — | `dword:00000000` |
| `VScrollUsageOverride` | — | — | `dword:00000000` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col01`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col01\a&eaf9d13&2&0000`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Address` | `dword:00000001` | `dword:00000001` | `dword:00000001` |
| `Capabilities` | `dword:000000a0` | `dword:000000a0` | `dword:000000a0` |
| `ClassGUID` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}"` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}"` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}"` |
| `CompatibleIDs` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@keyboard.inf,%hid.keyboarddevice%;HID Keyboar...` | `"@keyboard.inf,%hid.keyboarddevice%;HID Keyboar...` | `"@keyboard.inf,%hid.keyboarddevice%;HID Keyboar...` |
| `Driver` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}\\0000"` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}\\0000"` | `"{4d36e96b-e325-11ce-bfc1-08002be10318}\\0000"` |
| `HardwareID` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | `"@keyboard.inf,%std-keyboards%;(Standard keyboa...` | `"@keyboard.inf,%std-keyboards%;(Standard keyboa...` | `"@keyboard.inf,%std-keyboards%;(Standard keyboa...` |
| `Service` | `"kbdhid"` | `"kbdhid"` | `"kbdhid"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col01\a&eaf9d13&2&0000\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col02`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col02\a&eaf9d13&2&0001`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Address` | `dword:00000002` | `dword:00000002` | `dword:00000002` |
| `Capabilities` | `dword:000000e0` | `dword:000000e0` | `dword:000000e0` |
| `ClassGUID` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` |
| `Driver` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0004"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0004"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0004"` |
| `HardwareID` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col02\a&eaf9d13&2&0001\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col03`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col03\a&eaf9d13&2&0002`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `Address` | `dword:00000003` | `dword:00000003` | `dword:00000003` |
| `Capabilities` | `dword:000000e0` | `dword:000000e0` | `dword:000000e0` |
| `ClassGUID` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` |
| `CompatibleIDs` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | `dword:00000000` |
| `ContainerID` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` | `"{49c4a341-7dbd-5fb0-9f4a-84fa5ab58e77}"` |
| `DeviceDesc` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` | `"@hidserv.inf,%hid_device_system_consumer%;HID-...` |
| `Driver` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0013"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0013"` | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0013"` |
| `HardwareID` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` |
| `Mfg` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` | `"@hidserv.inf,%microsoft.mfg%;Microsoft"` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239&Col03\a&eaf9d13&2&0002\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col01`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col01\a&137e1bf2&1&0000`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000001` | — |
| `Capabilities` | — | `dword:000000a0` | — |
| `ClassGUID` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | — |
| `Driver` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0005"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@msmouse.inf,%msmfg%;Microsoft"` | — |
| `Service` | — | `"mouhid"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col01\a&137e1bf2&1&0000\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `FlipFlopHScroll` | — | `dword:00000000` | — |
| `FlipFlopWheel` | — | `dword:00000000` | — |
| `ForceAbsolute` | — | `dword:00000000` | — |
| `HScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `HScrollPageOverride` | — | `dword:00000000` | — |
| `HScrollUsageOverride` | — | `dword:00000000` | — |
| `VScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `VScrollPageOverride` | — | `dword:00000000` | — |
| `VScrollUsageOverride` | — | `dword:00000000` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col02`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col02\a&137e1bf2&1&0001`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000002` | — |
| `Capabilities` | — | `dword:000000a0` | — |
| `ClassGUID` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | — | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | — |
| `Driver` | — | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0006"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@msmouse.inf,%msmfg%;Microsoft"` | — |
| `Service` | — | `"mouhid"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col02\a&137e1bf2&1&0001\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `FlipFlopHScroll` | — | `dword:00000000` | — |
| `FlipFlopWheel` | — | `dword:00000000` | — |
| `ForceAbsolute` | — | `dword:00000000` | — |
| `HScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `HScrollPageOverride` | — | `dword:00000000` | — |
| `HScrollUsageOverride` | — | `dword:00000000` | — |
| `VScrollHighResolutionDisable` | — | `dword:00000000` | — |
| `VScrollPageOverride` | — | `dword:00000000` | — |
| `VScrollUsageOverride` | — | `dword:00000000` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col03`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col03\a&137e1bf2&1&0002`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | — | `dword:00000003` | — |
| `Capabilities` | — | `dword:000000e0` | — |
| `ClassGUID` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"` | — |
| `CompatibleIDs` | — | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | — | `dword:00000000` | — |
| `ContainerID` | — | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | — | `"@input.inf,%hid_device_vendor_defined_range%;H...` | — |
| `Driver` | — | `"{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0016"` | — |
| `HardwareID` | — | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | — | `"@input.inf,%stdmfg%;(Standard system devices)"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d&Col03\a&137e1bf2&1&0002\Device Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d\a&137e1bf2&1&0000`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `Address` | `dword:00000001` | `dword:00000001` | — |
| `Capabilities` | `dword:000000a0` | `dword:000000a0` | — |
| `ClassGUID` | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | `"{4d36e96f-e325-11ce-bfc1-08002be10318}"` | — |
| `CompatibleIDs` | `hex(7):00,00,00,00` | `hex(7):00,00,00,00` | — |
| `ConfigFlags` | `dword:00000000` | `dword:00000000` | — |
| `ContainerID` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | `"{a437e691-3b51-5dc3-9e4f-47e9f94f751d}"` | — |
| `DeviceDesc` | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | `"@msmouse.inf,%hid.mousedevice%;HID-compliant m...` | — |
| `Driver` | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0000"` | `"{4d36e96f-e325-11ce-bfc1-08002be10318}\\0000"` | — |
| `HardwareID` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | `hex(7):48,00,49,00,44,00,5c,00,7b,00,30,00,30,0...` | — |
| `Mfg` | `"@msmouse.inf,%msmfg%;Microsoft"` | `"@msmouse.inf,%msmfg%;Microsoft"` | — |
| `Service` | `"mouhid"` | `"mouhid"` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d\a&137e1bf2&1&0000\Device Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `FlipFlopHScroll` | `dword:00000000` | `dword:00000000` | — |
| `FlipFlopWheel` | `dword:00000000` | `dword:00000000` | — |
| `ForceAbsolute` | `dword:00000000` | `dword:00000000` | — |
| `HScrollHighResolutionDisable` | `dword:00000000` | `dword:00000000` | — |
| `HScrollPageOverride` | `dword:00000000` | `dword:00000000` | — |
| `HScrollUsageOverride` | `dword:00000000` | `dword:00000000` | — |
| `VScrollHighResolutionDisable` | `dword:00000000` | `dword:00000000` | — |
| `VScrollPageOverride` | `dword:00000000` | `dword:00000000` | — |
| `VScrollUsageOverride` | `dword:00000000` | `dword:00000000` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\applebmt`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `DisplayName` | `"@oem10.inf,%AppleWirelessMouse.SvcDesc%;Apple ...` | `"@oem10.inf,%AppleWirelessMouse.SvcDesc%;Apple ...` | — |
| `ErrorControl` | `dword:00000000` | `dword:00000000` | — |
| `ImagePath` | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` | — |
| `Owners` | `hex(7):6f,00,65,00,6d,00,31,00,30,00,2e,00,69,0...` | `hex(7):6f,00,65,00,6d,00,31,00,30,00,2e,00,69,0...` | — |
| `Start` | `dword:00000003` | `dword:00000003` | — |
| `Type` | `dword:00000001` | `dword:00000001` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\applebmt\Enum`

| Existence | 11-24: **YES** | 04-03: **no** | 04-27: **no** |
|---|---|---|---|
| `0` | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` | — | — |
| `Count` | `dword:00000001` | — | — |
| `NextInstance` | `dword:00000001` | — | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\applebmt\Parameters`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\applebmt\Parameters\Wdf`

| Existence | 11-24: **YES** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `WdfMajorVersion` | `dword:00000001` | `dword:00000001` | — |
| `WdfMinorVersion` | `dword:00000005` | `dword:00000005` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\applewirelessmouse`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **YES** |
|---|---|---|---|
| `DisplayName` | — | — | `"@oem0.inf,%AppleWirelessMouse.SvcDesc%;Apple W...` |
| `ErrorControl` | — | `dword:00000001` | `dword:00000000` |
| `Group` | — | — | `""` |
| `ImagePath` | — | `hex(2):53,00,79,00,73,00,74,00,65,00,6d,00,33,0...` | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` |
| `Owners` | — | — | `hex(7):6f,00,65,00,6d,00,30,00,2e,00,69,00,6e,0...` |
| `Start` | — | `dword:00000003` | `dword:00000003` |
| `Type` | — | `dword:00000001` | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\applewirelessmouse\Enum`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `0` | — | — | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` |
| `Count` | — | — | `dword:00000001` |
| `NextInstance` | — | — | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\applewirelessmouse\Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\applewirelessmouse\Parameters\Wdf`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `WdfMajorVersion` | — | — | `dword:00000001` |
| `WdfMinorVersion` | — | — | `dword:0000000f` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouse`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `DisplayName` | — | `"@oem53.inf,%Service.Desc%;Magic Mouse Service"` | — |
| `ErrorControl` | — | `dword:00000001` | — |
| `Group` | — | `""` | — |
| `ImagePath` | — | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` | — |
| `Owners` | — | `hex(7):6f,00,65,00,6d,00,35,00,33,00,2e,00,69,0...` | — |
| `Start` | — | `dword:00000003` | — |
| `Type` | — | `dword:00000001` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouse\Enum`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `0` | — | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` | — |
| `1` | — | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` | — |
| `Count` | — | `dword:00000002` | — |
| `NextInstance` | — | `dword:00000002` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouse\Parameters`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouse\Parameters\Wdf`

| Existence | 11-24: **no** | 04-03: **YES** | 04-27: **no** |
|---|---|---|---|
| `KmdfLibraryVersion` | — | `"1.15"` | — |
| `WdfMajorVersion` | — | `dword:00000001` | — |
| `WdfMinorVersion` | — | `dword:0000000f` | — |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `DeleteFlag` | — | — | `dword:00000001` |
| `DisplayName` | — | — | `"@oem52.inf,%ServiceDesc%;Magic Mouse Driver (s...` |
| `DriverDelete` | — | — | `dword:00000001` |
| `ErrorControl` | — | — | `dword:00000001` |
| `Group` | — | — | `""` |
| `ImagePath` | — | — | `hex(2):5c,00,53,00,79,00,73,00,74,00,65,00,6d,0...` |
| `Start` | — | — | `dword:00000004` |
| `Type` | — | — | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Enum`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `0` | — | — | `"BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb...` |
| `Count` | — | — | `dword:00000001` |
| `NextInstance` | — | — | `dword:00000001` |

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Parameters`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|

## `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Parameters\Wdf`

| Existence | 11-24: **no** | 04-03: **no** | 04-27: **YES** |
|---|---|---|---|
| `WdfMajorVersion` | — | — | `dword:00000001` |
| `WdfMinorVersion` | — | — | `dword:0000000f` |

