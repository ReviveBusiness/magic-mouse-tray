# M12 Style-Guide Report

**Generated:** 2026-04-29 02:39 MDT  
**Verdict:** **FAIL -- commit blocked**  
**Violations:** 7 REJECT / 22 FLAG / 0 WARN

## Hard failures (REJECT -- must fix before commit/PR)

- **[mixed-casing]** \`driver/Driver.c\` line -: File mixes snake_case and camelCase identifiers. Kernel driver files must use one consistent style (WDF convention: camelCase for locals, PascalCase for types, M12Prefix for functions).
- **[comment-density]** \`driver/HidDescriptor.c\` line -: Comment ratio 45.0% exceeds 25% limit (49 comment lines / 109 total). Microsoft samples run 5-15%.
- **[comment-density]** \`driver/InputHandler.c\` line -: Comment ratio 30.3% exceeds 25% limit (151 comment lines / 498 total). Microsoft samples run 5-15%.
- **[mixed-casing]** \`driver/InputHandler.c\` line -: File mixes snake_case and camelCase identifiers. Kernel driver files must use one consistent style (WDF convention: camelCase for locals, PascalCase for types, M12Prefix for functions).
- **[comment-density]** \`driver/Driver.h\` line -: Comment ratio 66.4% exceeds 25% limit (85 comment lines / 128 total). Microsoft samples run 5-15%.
- **[comment-density]** \`driver/HidDescriptor.h\` line -: Comment ratio 33.3% exceeds 25% limit (2 comment lines / 6 total). Microsoft samples run 5-15%.
- **[comment-density]** \`driver/InputHandler.h\` line -: Comment ratio 76.0% exceeds 25% limit (19 comment lines / 25 total). Microsoft samples run 5-15%.

## Soft flags (FLAG -- review required)

- **[generic-name]** \`driver/HidDescriptor.c\` line 10: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/HidDescriptor.c\` line 16: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/HidDescriptor.c\` line 26: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 213: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 312: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 349: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 377: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 384: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 531: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[helper-few-callers]** \`driver/InputHandler.c\` line 54: Static function 'BrbReadHandle' has only 2 caller(s). DRY threshold is 3+. Inline unless growth is planned; document rationale if kept.
- **[helper-few-callers]** \`driver/InputHandler.c\` line 64: Static function 'BrbReadPtr' has only 2 caller(s). DRY threshold is 3+. Inline unless growth is planned; document rationale if kept.
- **[helper-few-callers]** \`driver/InputHandler.c\` line 73: Static function 'StoreChannelHandle' has only 1 caller(s). DRY threshold is 3+. Inline unless growth is planned; document rationale if kept.
- **[helper-few-callers]** \`driver/InputHandler.c\` line 91: Static function 'ClearChannelHandle' has only 1 caller(s). DRY threshold is 3+. Inline unless growth is planned; document rationale if kept.
- **[helper-few-callers]** \`driver/InputHandler.c\` line 154: Static function 'ScanForSdpHidDescriptor' has only 1 caller(s). DRY threshold is 3+. Inline unless growth is planned; document rationale if kept.
- **[helper-few-callers]** \`driver/InputHandler.c\` line 214: Static function 'PatchSdpHidDescriptor' has only 1 caller(s). DRY threshold is 3+. Inline unless growth is planned; document rationale if kept.
- **[generic-name]** \`driver/Driver.h\` line 14: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 19: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 81: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 94: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 98: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 130: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.h\` line 9: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).


---
<!-- Generated by scripts/check-style.sh -->
