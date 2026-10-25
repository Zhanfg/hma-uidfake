#!/system/bin/sh
# HMA UIDFake opt candidate: device smoke test, no command arguments.
# Tests actual kernel module presence and Netlink/sync status. Optional strict
# load requires explicit interactive confirmation and uses the module's own KMI
# selector; this NEVER injects a mismatched module.
PATH=/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:$PATH
MOD=/data/adb/modules/hma-uidfake
OUTDIR=/sdcard/Download
[ -d "$OUTDIR" ] || OUTDIR=/data/local/tmp
TS=$(date +%Y%m%d_%H%M%S 2>/dev/null)
LOG="$OUTDIR/HMA_UIDFake_Smoke_${TS:-run}.txt"

run_test() {
  title="$1"; shift
  printf '\n[%s]\n' "$title"
  "$@" 2>&1
  rc=$?
  printf '[exit=%s]\n' "$rc"
  return "$rc"
}

check_loaded() {
  grep -q '^hma_uidfake ' /proc/modules 2>/dev/null || [ -d /sys/module/hma_uidfake ]
}

{
  echo 'HMA UIDFake on-device smoke test'
  date
  printf 'kernel=%s\n' "$(uname -r)"
  printf 'uid=%s\n' "$(id -u)"
  printf 'android=%s\n' "$(getprop ro.build.version.release)"
  printf 'fingerprint hash not exported; secrets will not be collected\n'
  if [ "$(id -u)" != 0 ]; then
    echo 'FAIL: this script must run as root to check module status.'
    exit 1
  fi
  if [ ! -d "$MOD" ]; then
    echo 'FAIL: /data/adb/modules/hma-uidfake missing; install the module ZIP first.'
    exit 1
  fi
  printf 'Module metadata:\n'
  grep -E '^(id|name|version|versionCode|description)=' "$MOD/module.prop" 2>/dev/null
  printf 'Selected KMI: '
  cat "$MOD/state/selected-kmi" 2>/dev/null || echo '<not selected>'
  printf '\nKO files: '
  find "$MOD/ko" -name '*_arm64_hma_uidfake.ko' -type f 2>/dev/null | wc -l
  printf 'Disable-load marker: '
  if [ -e /data/adb/hma-uidfake/disable_load ]; then echo 'present'; else echo 'absent'; fi
  if ! check_loaded; then
    echo 'STATUS: kernel module not loaded.'
    if [ -e /data/adb/hma-uidfake/disable_load ]; then
      echo 'Strict loading prohibited by disable marker.'
    elif [ ! -f "$MOD/load.sh" ]; then
      echo 'Missing module load.sh.'
    else
      echo 'You may optionally attempt a STRICT KMI-checked load.'
      echo 'WARNING: even a verified ABI can crash an incompatible phone.'
      echo 'To try loading interactively, type LOAD at the following prompt.'
      printf 'Enter LOAD (otherwise skip): '
      IFS= read -r reply </dev/tty 2>/dev/null || reply=''
      if [ "$reply" = 'LOAD' ]; then
        # Test original installed loader, not Manual inject.
        . "$MOD/load.sh"
        uidfake_load "$MOD"
      else
        echo 'Skipped live insertion.'
      fi
    fi
  fi
  if check_loaded; then
    echo 'PASS: hma_uidfake appears in the running kernel.'
  else
    echo 'FAIL: hma_uidfake not present in /proc/modules or sysfs.'
  fi
  if [ -x "$MOD/sync-tool" ]; then
    run_test 'Netlink status / live hooks and policy' "$MOD/sync-tool" --status
  else
    echo 'FAIL: sync-tool missing.'
  fi
  echo '[Recent load and synchronization messages]'
  for f in "$MOD/state/kernel-load.log" "$MOD/state/kmi.log" "$MOD/state/sync.log"; do
    if [ -f "$f" ]; then
      echo "--- $(basename "$f") ---"
      tail -n 25 "$f"
    fi
  done
  echo '[Kernel UIDFake diagnostics]'
  if command -v dmesg >/dev/null 2>&1; then
    dmesg 2>/dev/null | grep -i 'uidfake' | tail -n 25
  fi
  echo 'END: check PASS/FAIL and report status. Real functionality requires nonzero policy count and verified native hooks.'
} >"$LOG" 2>&1
cat "$LOG"
echo "Saved report: $LOG"