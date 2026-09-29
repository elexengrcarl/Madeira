"""CI: build the iOS unix sides against the iOS SDK of GitHub's runner (Xcode 26.6, iPhoneOS 26.5).

The development machine's SDK was newer:
  * build/ntdll-unix/server_ios.c's [xp] performance line reads rusage_info_v6's
    ri_page_wait_time_mach, which the runner's SDK does not declare. That one figure (pgw) is
    reported as 0; everything else in the line is unchanged.
Idempotent; run from the repository root.
"""
import sys

MARKER = "/* ci: runner SDK */"


def patch(path, anchor, replacement, what):
    s = open(path, encoding="utf-8", newline="").read()
    if MARKER in s:
        print(f"sdk-fixes: {what}: already applied")
        return
    if s.count(anchor) != 1:
        sys.exit(f"sdk-fixes: {what}: anchor found {s.count(anchor)} times in {path}")
    open(path, "w", encoding="utf-8", newline="").write(s.replace(anchor, replacement))
    print(f"sdk-fixes: {what}")


patch("build/ntdll-unix/server_ios.c",
      "XP_MS( ru.ri_page_wait_time_mach - pru.ri_page_wait_time_mach )",
      "0.0 " + MARKER,
      "server_ios.c: pgw without ri_page_wait_time_mach")
