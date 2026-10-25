#!/system/bin/sh
# PJZ110 / HMA UID Fake: read-only diagnosis of required native syscall hooks.
# No arguments; never calls insmod, finit_module, changes kptr_restrict, or edits rules.
umask 077
PATH=/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:$PATH
MOD=/data/adb/modules/hma-uidfake
OUT=/storage/emulated/0/Download
[ -d "$OUT" ] || OUT=/data/local/tmp
if [ "$(id -u)" != 0 ]; then
  echo "Root required. Run this script from your root-capable file manager."
  exit 1
fi
TS=$(date +%Y%m%d_%H%M%S)
REPORT="$OUT/HMA_NativeHook_Readonly_${TS}.txt"
{
  echo "HMA UID Fake native hook diagnosis (read-only)"
  date
  printf "root_uid=%s\n" "$(id -u)"
  printf "kernel_uname=%s\n" "$(uname -r)"
  printf "kernel_procversion=%s\n" "$(cat /proc/version 2>&1)"
  printf "device=%s\n" "$(getprop ro.product.model)"
  printf "android=%s\n" "$(getprop ro.build.version.release)"
  printf "SELinux=%s\n" "$(getenforce 2>&1)"
  printf "kptr_restrict=%s\n" "$(cat /proc/sys/kernel/kptr_restrict 2>&1)"
  echo
  echo "[Module and last failure]"
  if [ -r "$MOD/module.prop" ]; then
    grep -E '^(id|name|version|description)=' "$MOD/module.prop" | cut -c 1-440
  else
    echo "module.prop unavailable"
  fi
  for f in selected-kmi manual-requested-kmi kmi.log load.reason kernel-load.log manual-load.log; do
    echo "--- $f ---"
    if [ -r "$MOD/state/$f" ]; then
      tail -n 15 "$MOD/state/$f" | cut -c 1-440
    else
      echo "unavailable"
    fi
  done
  echo
  echo "[Module live state]"
  if grep -q '^hma_uidfake ' /proc/modules 2>/dev/null || [ -d /sys/module/hma_uidfake ]; then
    echo "hma_uidfake=present"
  else
    echo "hma_uidfake=absent"
  fi
  echo
  echo "[Required symbols: presence ONLY, no addresses]"
  echo "Kernel kallsyms listings may omit or mask symbols; absent != unresolved in kernel."
  if [ -r /proc/kallsyms ]; then
    awk '
      BEGIN {
        split("sys_call_table init_mm __set_fixmap kallsyms_lookup_name kallsyms_on_each_symbol __arm64_sys_getpriority __arm64_sys_setpriority __arm64_sys_ioprio_get __arm64_sys_ioprio_set __arm64_sys_getpriority.cfi_jt __arm64_sys_setpriority.cfi_jt __arm64_sys_ioprio_get.cfi_jt __arm64_sys_ioprio_set.cfi_jt", s, " ");
        for (i in s) { named[s[i]]=1; order[i]=s[i]; }
      }
      NF>=3 && ($3 in named) { seen[$3]=1; if ($1 !~ /^0+$/) nonzero[$3]=1; }
      END {
        for (i=1; i<=13; i++) {
          name=order[i];
          printf "%s : %s%s\n", name, seen[name] ? "listed" : "not-listed",
            nonzero[name] ? " (nonzero addr, not disclosed)" : "";
        }
      }
    ' /proc/kallsyms 2>&1
    printf "kallsyms_awk_exit=%s\n" "$?"
  else
    echo "Cannot read /proc/kallsyms"
  fi
  echo
  echo "[Kernel message access]"
  dmesg >/dev/null 2>&1
  drc=$?
  echo "dmesg_exit=$drc"
  if [ "$drc" -eq 0 ]; then
    (dmesg 2>&1 | grep -Ei 'uidfake|sys_call_table|unknown symbol|module verification|fixmap|vermagic|kernel rejected|hook' | tail -n 80) || :
  else
    dmesg 2>&1 | head -n 5
  fi
  echo
  echo "[Possible errno stages if current optimized KO reached module_init]"
  echo "38: first native getpriority hook slot not found"
  echo "42: native setpriority hook slot not found"
  echo "61: native ioprio_get hook slot not found"
  echo "126: native ioprio_set hook slot not found"
  echo "5: native table patch operation/verification failed"
  echo "Other loader errors or in-kernel errno collisions remain possible."
  echo "Do not expose complete /proc/kallsyms, APK rules or sensitive application data."
} > "$REPORT" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  cat "$REPORT"
  printf "\nReport saved: %s\n" "$REPORT"
else
  echo "Failed to write report (rc=$rc)"
fi
exit "$rc"
