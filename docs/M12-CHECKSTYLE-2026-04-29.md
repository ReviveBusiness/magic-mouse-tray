# M12 Style-Guide Report

**Generated:** 2026-04-29 02:26 MDT  
**Verdict:** **FAIL -- commit blocked**  
**Violations:** 14 REJECT / 19 FLAG / 0 WARN

## Hard failures (REJECT -- must fix before commit/PR)

- **[mixed-casing]** \`driver/Driver.c\` line -: File mixes snake_case and camelCase identifiers. Kernel driver files must use one consistent style (WDF convention: camelCase for locals, PascalCase for types, M12Prefix for functions).
- **[clang-format]** \`driver/Driver.c\` line -: clang-format reports formatting violations. Run: clang-format --style=file:/home/lesley/.claude/worktrees/ai-m12-script-tests/driver/.clang-format -i driver/Driver.c. Output: /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/Driver.c:7:13: error: code should be clang-formatted [-Wclang-format-violations]; DriverEntry(;             ^; /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/Driver.c:8:24: error: code should be clang-formatted [-Wclang-format-violati
- **[comment-density]** \`driver/HidDescriptor.c\` line -: Comment ratio 40.3% exceeds 25% limit (54 comment lines / 134 total). Microsoft samples run 5-15%.
- **[mixed-casing]** \`driver/HidDescriptor.c\` line -: File mixes snake_case and camelCase identifiers. Kernel driver files must use one consistent style (WDF convention: camelCase for locals, PascalCase for types, M12Prefix for functions).
- **[clang-format]** \`driver/HidDescriptor.c\` line -: clang-format reports formatting violations. Run: clang-format --style=file:/home/lesley/.claude/worktrees/ai-m12-script-tests/driver/.clang-format -i driver/HidDescriptor.c. Output: /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/HidDescriptor.c:40:16: error: code should be clang-formatted [-Wclang-format-violations];     0x05, 0x01,        // Usage Page (Generic Desktop);                ^; /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/HidDescriptor.c:41:16: 
- **[comment-density]** \`driver/InputHandler.c\` line -: Comment ratio 32.4% exceeds 25% limit (133 comment lines / 411 total). Microsoft samples run 5-15%.
- **[mixed-casing]** \`driver/InputHandler.c\` line -: File mixes snake_case and camelCase identifiers. Kernel driver files must use one consistent style (WDF convention: camelCase for locals, PascalCase for types, M12Prefix for functions).
- **[clang-format]** \`driver/InputHandler.c\` line -: clang-format reports formatting violations. Run: clang-format --style=file:/home/lesley/.claude/worktrees/ai-m12-script-tests/driver/.clang-format -i driver/InputHandler.c. Output: /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/InputHandler.c:54:29: error: code should be clang-formatted [-Wclang-format-violations]; static FORCEINLINE ULONG_PTR;                             ^; /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/InputHandler.c:55:15: error: code sho
- **[comment-density]** \`driver/Driver.h\` line -: Comment ratio 70.7% exceeds 25% limit (82 comment lines / 116 total). Microsoft samples run 5-15%.
- **[clang-format]** \`driver/Driver.h\` line -: clang-format reports formatting violations. Run: clang-format --style=file:/home/lesley/.claude/worktrees/ai-m12-script-tests/driver/.clang-format -i driver/Driver.h. Output: /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/Driver.h:39:38: error: code should be clang-formatted [-Wclang-format-violations]; #define IOCTL_INTERNAL_BTH_SUBMIT_BRB    0x00410003UL;                                      ^; /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/Driver.h:
- **[comment-density]** \`driver/HidDescriptor.h\` line -: Comment ratio 28.6% exceeds 25% limit (2 comment lines / 7 total). Microsoft samples run 5-15%.
- **[mixed-casing]** \`driver/HidDescriptor.h\` line -: File mixes snake_case and camelCase identifiers. Kernel driver files must use one consistent style (WDF convention: camelCase for locals, PascalCase for types, M12Prefix for functions).
- **[clang-format]** \`driver/HidDescriptor.h\` line -: clang-format reports formatting violations. Run: clang-format --style=file:/home/lesley/.claude/worktrees/ai-m12-script-tests/driver/.clang-format -i driver/HidDescriptor.h. Output: /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/HidDescriptor.h:6:19: error: code should be clang-formatted [-Wclang-format-violations]; extern const UCHAR  g_HidDescriptor[];;                   ^; /home/lesley/.claude/worktrees/ai-m12-script-tests/driver/HidDescriptor.h:7:19: error: code sho
- **[comment-density]** \`driver/InputHandler.h\` line -: Comment ratio 73.7% exceeds 25% limit (14 comment lines / 19 total). Microsoft samples run 5-15%.

## Soft flags (FLAG -- review required)

- **[generic-name]** \`driver/HidDescriptor.c\` line 10: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/HidDescriptor.c\` line 16: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/HidDescriptor.c\` line 26: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 201: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 296: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 318: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 348: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 354: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.c\` line 446: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 14: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 19: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 84: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 97: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 101: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/Driver.h\` line 127: Generic identifier 'buffer' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.h\` line 9: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.h\` line 19: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.h\` line 20: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).
- **[generic-name]** \`driver/InputHandler.h\` line 21: Generic identifier 'data' detected. Use domain-specific WDF/HID terms (reqContext, devCtx, batteryStatus, etc.).


---
<!-- Generated by scripts/check-style.sh -->
