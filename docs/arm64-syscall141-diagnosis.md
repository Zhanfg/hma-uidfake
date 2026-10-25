# ARM64 native syscall 141 mismatch: triage note

Scope: HMA UID Fake, GKI `android15-6.6`, OnePlus 13 / PJZ110. This is a **diagnostic** note; it is not a verified fix.

## Evidence already observed

- Installed opt3 KO is identical to the CI artifact (SHA256 `da28430e4bfacd94691e01eeec25624694af1420a43c3cfb83b1779c848937a2`).
- A strict module insertion entered initialization; `kaux` Netlink registration returned 0.
- `task_fix_setuid` LSM installation returned -2, so its existing fallback path was attempted.
- Symbol lookup for `__arm64_sys_getpriority` returned a candidate, but no matching entry was found in the scanned native syscall table. The module returned `-ENOSYS` and remained unloaded.
- On ARM64 the native `getpriority` syscall number is 141; `setpriority` is 140. Compat AArch32 uses different numbering.
- `uname -r` and `/proc/version` reported distinct release identifiers; this is worth investigating separately but is **not** established as the cause of the mismatch.

## What is and is not proven

The error is an actual required-hook match failure within module initialization. A symbol *name* visible in `/proc/kallsyms` does not prove that its address matches the function pointer currently held by `sys_call_table[141]`.

It is not yet established whether the kernel uses a different wrapper/alias, whether another component replaced the original table entry, or whether the symbol resolver chose a wrong target. Loaded module names can help inventory the environment, but cannot attribute the mismatch by themselves.

## Safe next steps

1. Capture read-only kernel build identity, relevant symbol names (never raw addresses), loaded module names, installed KO checksum, and latest module messages.
2. Distinguish stale loader logs from logs of a known single insertion attempt.
3. Review any identified divergence against the **exact running kernel's source/build**, rather than generic GKI headers.
4. Test on an isolated device/kernel with a supported diagnostic interface before changing any required hook installation logic.

**Do not** treat the mismatch as permission to patch an unverified table entry, discard required hooks, skip module signature/KMI checks, or call an untyped pointer. Keep the PR in draft until real-device load and functional validation pass.

## Public implementation references

- Android kernel ARM64 table initialization: `arch/arm64/kernel/sys.c`
- Android ARM64 syscall invocation: `arch/arm64/kernel/syscall.c`
- Generic syscall numbers: `include/uapi/asm-generic/unistd.h`

