# Code Quality Reviewer -- Review Template

## Role

Code quality and modularity specialist. Evaluates DRY discipline, module cohesion,
reference-implementation traceability, error handling completeness (neither paranoid
nor incomplete), and test coverage. The lens is: "would a senior engineer on the
Windows driver team approve this design as maintainable production code?"

---

## Required reading (always)

1. The PR diff (every .c, .h, .inf, test file)
2. docs/M12-AUTONOMOUS-DEV-FRAMEWORK.md -- reference implementation table (every
   M12 function must name its Microsoft sample model)
3. docs/M12-DESIGN-SPEC.md -- Section 9 (function signatures), Section 10 (data structures),
   Section 11 (failure mode table F1-F12)

---

## Required reading (per topic)

| Topic | Reference |
|---|---|
| DRY threshold | docs/M12-AUTONOMOUS-DEV-FRAMEWORK.md style guide: "extract only if 3+ callers" |
| Reference implementations | docs/M12-REFERENCE-INDEX.md; Microsoft firefly, kbfiltr, moufiltr |
| Error handling | KMDF best practices; NTSTATUS early-exit pattern |
| Test patterns | Microsoft KMDF user-mode test samples; M12-DESIGN-SPEC.md Section TEST-1 |
| Module layout | M12-DESIGN-SPEC.md Section 9 (InputHandler.c, IoctlHandlers.c, BatteryReader.c) |

---

## Review checklist

Copy this block verbatim into your review output. Mark each item PASS / FAIL / N/A.
For every FAIL, cite file + line and provide recommended fix.

```
[ ] 1.  DRY THRESHOLD (EXTRACT HELPER ONLY IF 3+ CALLERS)
        - For every non-event-callback function in the diff: count its call sites
          across the codebase. If < 3 call sites, the function should be inlined
          at its single call site (or at most two, if they are symmetrical and
          the extraction genuinely reduces cognitive load).
        - Exception: functions extracted for testability (mocked in user-mode test
          harness). These are acceptable with < 3 callers IF they appear in the
          test harness as a seam.
        - Exception: functions that implement a named algorithm (TranslateBatteryRaw,
          ExtractTouchPoints) are acceptable as named functions regardless of call count,
          because they represent a distinct operation with a defined spec.
        - FAIL: trivial wrapper functions (GetContext, SetFlag, CheckNull) with
          < 3 call sites and < 5 lines of body. These are AI-style "clean code"
          extractions that add indirection without value.

[ ] 2.  MODULE COHESION
        - InputHandler.c: contains only IRP-level input processing (touch report
          parsing, button events, scroll translation). No battery logic in this module.
        - IoctlHandlers.c: contains only IOCTL dispatch and response assembly
          (GET_FEATURE, GET_DESCRIPTOR, GET_ATTRIBUTES, GET_DEVICE_DESCRIPTOR).
          No raw BT packet parsing in this module.
        - BatteryReader.c: contains shadow buffer management, battery extraction,
          translation formula. No IOCTL dispatch in this module.
        - Driver.c: contains DriverEntry, EvtDriverDeviceAdd, device context
          initialization only. No business logic in Driver.c.
        - Each .c file imports only headers it directly uses. No convenience
          "include everything" header (AllHeaders.h, Common.h that re-exports
          unrelated types).
        - Cross-module calls go only downward (Driver -> modules; no module calls Driver).

[ ] 3.  REFERENCE-IMPLEMENTATION CITATION (EACH FUNCTION NAMES ITS MODEL)
        - For every function in the diff that is NOT a direct WDF event callback
          boilerplate: a comment in the function body or at its declaration cites
          the reference implementation it is modeled on.
          Format: "// Modeled on Microsoft firefly::FilterEvtIoDeviceControl."
          OR: "// No prior art; design rationale: [reason]."
        - Functions with no citation and no "no prior art" note are flagged.
        - Reference table in docs/M12-AUTONOMOUS-DEV-FRAMEWORK.md is authoritative.
          Every function in that table MUST have a matching citation in the code.
        - If a PR introduces a new function NOT in the reference table, the PR
          description must explain why no reference exists and what design decision
          the function implements.

[ ] 4.  ERROR HANDLING COMPLETENESS (WITHOUT PARANOID EXTRAS)
        - Every WDF API call that returns NTSTATUS has its return value checked.
          No unchecked WdfSomething() call where failure would leave the driver
          in an inconsistent state.
        - Every checked failure is followed by a meaningful recovery action:
            - Return the error status upstream (most common).
            - Complete the IRP with the failure status.
            - Log via WPP at appropriate level (TRACE_LEVEL_ERROR for unexpected,
              TRACE_LEVEL_INFORMATION for expected transient failures).
        - No "just in case" error paths for things that cannot fail per WDF contract.
          Example of FAIL: checking WdfDeviceCreate return value with a comment
          "// should not fail but just in case." WdfDeviceCreate does fail; check
          it. But if WdfDeviceGetIoTarget is called after a successful WdfDeviceCreate,
          it cannot return NULL -- do not check for NULL with a comment "just in case."
        - NTSTATUS propagated, not converted to bool or int at any call boundary.
        - Failure mode table (F1-F12 in design spec) coverage: each F-item has
          a corresponding error path in code. If a failure mode has no error path,
          it must be N/A (design says it cannot happen) with justification.

[ ] 5.  FUNCTION PRECONDITIONS DOCUMENTED
        - Functions with non-obvious preconditions have a comment block stating them:
            // Preconditions: called at IRQL <= DISPATCH_LEVEL.
            //                ctx->ShadowBuffer not NULL (set in EvtDevicePrepareHardware).
            //                SpinLock not held by caller.
        - IRQL requirements stated for every function that acquires a spin lock
          or calls a DISPATCH_LEVEL-only API.
        - Functions that MUST NOT be called after device removal have a comment
          noting the lifetime constraint.
        - NT_ASSERT statements used in debug builds to enforce preconditions:
            NT_ASSERT(KeGetCurrentIrql() <= DISPATCH_LEVEL);
            NT_ASSERT(ctx->Signature == M12_CONTEXT_SIGNATURE);
          These are stripped by the compiler in release builds -- no overhead.

[ ] 6.  TEST COVERAGE ASSESSMENT
        - User-mode test harness exists for pure-logic functions (BatteryTranslate,
          descriptor byte generation, touch point parsing). These run without
          installing the driver.
        - Each test file has at minimum: one nominal case, one boundary case
          (min/max input values), one invalid-input case (rejection path).
        - Test functions named after the thing they test plus the scenario:
            Test_TranslateBatteryRaw_MinValue, Test_TranslateBatteryRaw_MaxValue,
            Test_TranslateBatteryRaw_OutOfRange.
          NOT: TestBattery1, testFunc, test_helper.
        - Coverage threshold: every public function in BatteryReader.c and
          InputHandler.c has at least one test. IoctlHandlers.c functions that
          do NOT forward to IoTarget (static-response IOCTLs) have tests.
        - Test output is deterministic: no dependency on system state, registry,
          real device, or wall-clock time.
        - Tests pass on clean Windows build environment without driver installed.
```

---

## Verdict format

```
VERDICT: APPROVE | CHANGES-NEEDED | REJECT

MAJOR (count=N):           [must fix before merge]
  MAJ-1: [checklist item] [file:line] [description] [fix]
  ...

MINOR (count=N):           [improve before merge or document justification]
  MIN-1: [checklist item] [file:line] [description] [recommendation]
  ...

CONFIRMED QUALITY (list):
  - [Each checklist item confirmed PASS]

TEST COVERAGE SUMMARY:
  Functions with coverage: N / M
  Uncovered functions: [list]
  Assessment: [ADEQUATE | INADEQUATE]

REFERENCE CITATION STATUS:
  Functions cited: N / M
  Uncited functions: [list -- each requires action]
```

Threshold: APPROVE requires 0 major, <=3 minor, test coverage ADEQUATE.
CHANGES-NEEDED: any major or test coverage INADEQUATE.
REJECT: only if module cohesion is so broken that the PR cannot be fixed without
a structural rewrite (rare; flag as REJECT with explanation).

---

## Anti-patterns to reject

1. Business logic in Driver.c. DriverEntry and EvtDriverDeviceAdd are wiring code.
   If they contain input parsing, battery calculation, or IOCTL dispatch logic,
   that logic belongs in the appropriate module.
2. Cross-module dependency inversion: a low-level module (BatteryReader.c) calling
   functions in a high-level module (IoctlHandlers.c). This creates circular
   dependencies that KMDF drivers don't need.
3. Helper functions for trivial ops with < 3 callers and no test-seam justification.
   This is an AI-quality-code pattern, not an expert-driver-code pattern.
4. Unchecked WDF API return values where failure leaves driver state inconsistent.
   "It should not fail" is not a justification for skipping the check.
5. Test functions with names like test1, testFunc, test_helper. Names must describe
   what they test and under what condition.
6. Functions with no reference citation and no "no prior art" justification. Every
   function must trace to a model or explain why it is novel.
7. IRQL requirements undocumented for any function that acquires a spinlock. IRQL
   bugs are among the hardest kernel bugs to diagnose without this information.

---

## How to dispatch

```bash
python3 /home/lesley/projects/RILEY/scripts/agent.py spawn \
  --tier sonnet \
  --template .ai/agent-templates/code-quality-review.md \
  --pr-url <PR>
```

Attach: PR diff, docs/M12-DESIGN-SPEC.md Section 9 and 11, docs/M12-REFERENCE-INDEX.md.
Post structured verdict as a PR comment.
