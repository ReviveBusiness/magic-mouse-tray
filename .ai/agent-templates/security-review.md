# Security Reviewer -- Review Template

## Role

Kernel security specialist focused on attack surface, privilege escalation, and
safe-coding requirements for a Windows kernel-mode HID filter driver. Every finding
is evaluated from the perspective of a local low-privilege attacker who can open
handles to device interfaces and send arbitrary IOCTL payloads.

---

## Required reading (always)

1. The PR diff (every .c, .h, .inf, .ps1, .pfx-handling-script change)
2. docs/M12-DESIGN-SPEC.md -- Section 4 (SDDL / device interface), Section 7 (IOCTL handlers),
   Section 10 (data structures), Section 11 F3-F6 (failure modes: input validation, privilege)
3. .ai/playbooks/autonomous-agent-team.md -- AP catalogue

---

## Required reading (per topic)

| Topic | Reference |
|---|---|
| SDDL for device objects | MSDN: IoCreateDeviceSecure, SDDL_DEVOBJ_* constants |
| IOCTL buffer validation | MSDN: METHOD_BUFFERED, METHOD_NEITHER; WdfRequestRetrieve* |
| Kernel pool safety | MSDN: ExAllocatePoolWithTag, NonPagedPoolNx, pool tag tracking |
| IRP cancellation races | MSDN: TOCTOU on IRP fields; IoCancelIrp timing |
| Cert trust install | M12-DESIGN-SPEC.md signing strategy; scripts/install-m12-trust.ps1 |
| Driver signing chain | MSDN: test-sign policy, signtool /fd SHA256; W11 enforcement |
| WPP tracing / debug info | MSDN: WPP macros; DbgPrint in release builds |
| Registry TOCTOU | MSDN: ZwOpenKey / ZwQueryValueKey; concurrent writer attack |

---

## Review checklist

Copy this block verbatim into your review output. Mark each item PASS / FAIL / N/A.
For every FAIL, cite file + line and provide recommended fix.

```
[ ] 1.  IOCTL INPUT VALIDATION (BOUNDS, TYPE, RANGE)
        - Every IOCTL handler validates InputBufferLength and OutputBufferLength
          before accessing any byte of the buffer.
        - HID_XFER_PACKET.reportBufferLen checked >= minimum required size before
          offset read. No fixed-size cast without length pre-check.
        - User-controlled numeric fields (e.g., scroll speed from registry or IOCTL
          payload) are clamped to [min, max] at first read; no arithmetic using
          unclamped values. Division-by-zero impossible post-clamp.
        - Array index derived from user-controlled data is bounds-checked before use.
        - If a parser accepts a variable-length blob (e.g., vendor report 0x27 at 46
          bytes), the actual received length is validated against declared length
          before any offset access.

[ ] 2.  SDDL ON DEVICE INTERFACES (ADMIN-ONLY FOR SENSITIVE OPERATIONS)
        - Device interface SDDL (IoCreateDeviceSecure or
          WdfDeviceCreateDeviceInterface SDDL string) restricts sensitive IOCTLs
          to administrators (SID: BA = BUILTIN\Administrators).
        - The tray (userland) reads the battery Feature 0x47 via a HidD_ call on
          the HidClass interface, which Windows restricts to the device's declared
          access. Verify tray does not require raw device handle to the filter's
          custom interface.
        - If a custom IOCTL interface exists (power-saver suspend IOCTL):
          SDDL restricts to admins. Low-privilege process cannot trigger suspend.
        - WPP trace consumer: GUID protected from unauthorized access (not world-readable).

[ ] 3.  BUFFER OVERFLOW IN VENDOR BLOB PARSING
        - M12 v1.7 is pure passthrough for all vendor blobs except battery extraction.
          If any byte from vendor blob is copied into a stack buffer or fixed-size
          kernel buffer, destination size >= source size is verified.
        - If vendor blob parsing is present: every offset access is preceded by
          a length check. No memcpy/RtlCopyMemory with a length derived from
          user/device-provided data without prior validation.
        - Stack allocation for receive buffers: within safe IRQL and size limits.
          No variable-length stack allocations (alloca / dynamic arrays).
        - If M12 v1.7 is truly passthrough with no blob parsing beyond battery byte:
          verify there is no parsing code path that will be reached with malformed input.

[ ] 4.  RACE CONDITIONS (TOCTOU ON REGISTRY READS)
        - Registry parameters (scroll speed, battery offset, SDDL override) are read
          once at EvtDeviceAdd and cached in DEVICE_CONTEXT. Not re-read per IRP.
        - If any registry value is re-read at runtime: concurrent writer race analyzed.
          A malicious user modifying HKLM\...\Parameters between read and use cannot
          produce a kernel panic or privilege escalation.
        - KSPIN_LOCK or sequential IOCTL queue prevents concurrent mutation of
          shared fields (battery cache, shadow buffer). TOCTOU window on cache
          update is bounded and safe (worst case: stale value, not corruption).

[ ] 5.  PRIVILEGE ESCALATION SURFACE
        - No kernel-mode code path triggers based on user-provided data without
          validating that the caller has appropriate privileges.
        - Suspend IOCTL (if present) is guarded by SDDL admin-only; not reachable
          by low-privilege process.
        - Device object permissions prevent untrusted callers from opening the
          M12 device object directly; all battery reads go via HidClass.
        - PnP device interface GUID is not predictable / spoofable by a low-privilege
          process attempting to intercept the battery read path.
        - No kernel callback registered (PsSetCreateProcessNotifyRoutine etc.) unless
          explicitly justified and scoped to M12 functionality.

[ ] 6.  POOL TAG FOR DV / LEAK DETECTION
        - Pool tag 'M12 ' (or project-decided 4-char tag) used on ALL
          ExAllocatePoolWithTag calls.
        - Pool type NonPagedPoolNx for all kernel allocations (execute-disable;
          mandatory W10 W11 kernel hardening).
        - No ExAllocatePool (without tag) calls.
        - WDF object context memory: WDF manages this; verify no manual alloc
          of context outside WDF object lifetime.
        - DEVICE_CONTEXT Signature field asserted before each dereference in
          debug builds (NT_ASSERT(ctx->Signature == M12_CONTEXT_SIGNATURE)).

[ ] 7.  CRASH DUMP / DEBUG INFO LEAK
        - No DbgPrint, KdPrint, or DbgBreakPoint in release (non-debug) builds.
          All debug output via WPP macros with compile-time level control.
        - WPP logger does not emit raw user data (e.g., vendor blob bytes) at
          default trace level. Vendor data only at TRACE_LEVEL_VERBOSE.
        - .pdb file not included in production package; stripped before distribution.
        - Kernel crash dumps: M12 does not store sensitive user data in non-paged
          pool beyond transient IRP processing window.

[ ] 8.  SIGNED BINARY CHAIN (CERT-TRUST PATH)
        - .sys file is Authenticode signed with the M12 self-signed cert.
        - signtool /fd SHA256 /tr <RFC-3161> /td SHA256 (NOT legacy /t SHA1;
          W11 22H2+ kernel rejects SHA1 timestamps for test-signed drivers).
        - install-m12-trust.ps1: verifies cert thumbprint before trust-store install.
          Does NOT trust arbitrary certs; specifically adds M12 thumbprint to
          Trusted Publishers and Trusted Root CA (test mode only).
        - Script checks that Windows test signing is already enabled (bcdedit
          /set testsigning on) before installing. Does not silently enable test
          signing without user knowledge.
        - Driver loaded only under test-signing mode; production policy: no
          EV cert in scope (user decision). No code attempts to bypass SecureBoot
          or disable Driver Signing Enforcement.

[ ] 9.  CERT .PFX STORAGE (OFFLINE)
        - .pfx file is NOT committed to the git repository.
        - .pfx file path referenced in scripts is a local filesystem path
          documented as "generate locally; do not share."
        - .gitignore includes *.pfx.
        - install-m12-trust.ps1 imports the public cert (.cer) only;
          private key (.pfx) never leaves the build machine.
        - Build script comment explains: "regenerate .pfx with scripts/gen-cert.ps1;
          do not store in source control."
```

---

## Verdict format

```
VERDICT: APPROVE | CHANGES-NEEDED | REJECT

CRITICAL (count=N):        [blocks merge; immediate security risk]
  CRIT-1: [file:line] [vulnerability description] [remediation]
  ...

MAJOR (count=N):           [must fix before merge; not immediately exploitable but surface exists]
  MAJ-1: [file:line] [description] [remediation]
  ...

MINOR (count=N):           [hardening recommendations; fix or document justification]
  MIN-1: [file:line] [description] [recommendation]
  ...

CONFIRMED SECURE (list):
  - [Each topic confirmed secure]

THREAT SURFACE SUMMARY:
  [2-3 sentence summary of the overall attack surface M12 exposes]
```

Threshold: APPROVE requires 0 critical, 0 major.
CHANGES-NEEDED: 0 critical, any major.
REJECT: any critical.

---

## Anti-patterns to reject

1. Buffer access using user-provided length without prior bounds check. In kernel,
   this is a guaranteed BSOD or kernel memory corruption.
2. NonPagedPool (without Nx suffix) for any kernel allocation on W10/W11. Violates
   execute-disable mitigation; DV flags it.
3. .pfx or private key material in the git repository. Even if the cert is self-signed,
   committing it allows an attacker to sign arbitrary code with the same trust chain.
4. DbgPrint in release builds. Leaks internal driver state to any trace consumer
   with appropriate permissions. Use WPP with compile-time level control.
5. Custom IOCTL interface open to low-privilege callers. Any IOCTL that can trigger
   device state change (suspend, parameter write) must be admin-only via SDDL.
6. Registry read inside IRP dispatch path without caching. TOCTOU window between
   ZwOpenKey and ZwQueryValueKey allows a concurrent writer to change parameters
   mid-dispatch, producing unexpected driver behavior.
7. Division with denominator derived from user-controlled registry value without clamp.
   Registry key set to 0 produces divide-by-zero bugcheck in kernel.

---

## How to dispatch

```bash
python3 /home/lesley/projects/RILEY/scripts/agent.py spawn \
  --tier sonnet \
  --template .ai/agent-templates/security-review.md \
  --pr-url <PR>
```

Attach: PR diff, docs/M12-DESIGN-SPEC.md sections 4, 7, 10, 11.
Post structured verdict as a PR comment.
