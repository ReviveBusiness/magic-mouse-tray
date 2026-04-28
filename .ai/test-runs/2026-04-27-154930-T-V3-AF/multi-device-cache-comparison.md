# BTHPORT cache comparison — paired Apple devices + sibling

Captured: 2026-04-28 09:38

| MAC | Name | Cache | DescLen | Mouse TLC | Wheel | Vendor | Battery (UP=FF00,U=14) | Keyboard TLC | Consumer TLC |
|---|---|---|---|---|---|---|---|---|---|
| `04f13eeede10` | Trevor’s Mouse | 337B | 98 | YES | NO | NO | NO | NO | NO |
| `b2227a7a501b` | ENVY 6000 series | - | 0 | - | - | - | - | - | - |
| `d0c050cc8c4d` | Magic Mouse | 351B | 135 | YES | NO | YES | YES | NO | NO |
| `e806884b0741` | Trevor’s Keyboard | 454B | 224 | NO | NO | NO | NO | YES | YES |

## Per-device detail

### `04f13eeede10` — Trevor’s Mouse

- Cache value name: `00010000`  size: 337 bytes
- HID descriptor present: True  length: 98
- Mouse TLC (UP=0x01,U=0x02): **True**
- Wheel (UP=0x01,U=0x38): **False**
- AC Pan (UP=0x0C,U=0x238): **False**
- Vendor page 0xFF00 declared: **False**
- Vendor battery TLC (UP=0xFF00,U=0x14): **False**
- Keyboard TLC (UP=0x01,U=0x06): **False**
- Consumer TLC (UP=0x0C,U=0x01): **False**
- Input reports: [(16, 9, 2), (16, 9, 2), (16, 1, 49)]
- Output reports: []
- Feature reports: [(71, 6, 32), (85, 65282, 85)]

### `b2227a7a501b` — ENVY 6000 series

No SDP cache blob — device probably never queried by SDP recently.

### `d0c050cc8c4d` — Magic Mouse

- Cache value name: `00010000`  size: 351 bytes
- HID descriptor present: True  length: 135
- Mouse TLC (UP=0x01,U=0x02): **True**
- Wheel (UP=0x01,U=0x38): **False**
- AC Pan (UP=0x0C,U=0x238): **False**
- Vendor page 0xFF00 declared: **True**
- Vendor battery TLC (UP=0xFF00,U=0x14): **True**
- Keyboard TLC (UP=0x01,U=0x06): **False**
- Consumer TLC (UP=0x0C,U=0x01): **False**
- Input reports: [(18, 9, 2), (18, 9, 2), (18, 1, 49), (18, 1, 49), (144, 133, 70), (144, 133, 70), (144, 133, 101)]
- Output reports: []
- Feature reports: [(85, 65282, 85)]

### `e806884b0741` — Trevor’s Keyboard

- Cache value name: `00010000`  size: 454 bytes
- HID descriptor present: True  length: 224
- Mouse TLC (UP=0x01,U=0x02): **False**
- Wheel (UP=0x01,U=0x38): **False**
- AC Pan (UP=0x0C,U=0x238): **False**
- Vendor page 0xFF00 declared: **False**
- Vendor battery TLC (UP=0xFF00,U=0x14): **False**
- Keyboard TLC (UP=0x01,U=0x06): **True**
- Consumer TLC (UP=0x0C,U=0x01): **True**
- Input reports: [(1, 7, 6), (1, 7, 6), (1, 7, 6), (71, 6, 32), (17, 12, 1), (17, 12, 184), (17, 255, 3), (17, 255, 3), (18, 12, 205), (18, 12, 179), (18, 12, 180), (18, 12, 181), (18, 12, 182), (18, 12, 182), (18, 12, 182), (18, 12, 182), (19, 65281, 10), (19, 65281, 12), (19, 65281, 12)]
- Output reports: [(1, 8, 6), (1, 8, 6)]
- Feature reports: [(9, 65281, 11), (9, 65281, 11)]

