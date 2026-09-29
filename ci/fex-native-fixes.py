"""CI: make the pinned FEX build as the native iOS library the app links (FEX/build-ios).

Core.cpp's iOS probes ([ffs-bypass], [cb-entry]) read IosFfsBypassLog/IosCbEntryLog outside any
#ifdef, but declare them only under FEX_IOS_HOST - the define of the Windows-PE modules built for
the iOS host (xtajit64.dll, xtajit.dll), which also pulls in Win32 code (VirtualQuery) that a
native Mach-O build cannot compile. The native library therefore gets zeroed counters: the
reporters compare against values nothing increments, exactly as the WOW64 module's own fallback
does. Idempotent; run from the repository root.
"""
import sys

p = "FEX/FEXCore/Source/Interface/Core/Core.cpp"
s = open(p, encoding="utf-8", newline="").read()
marker = "/* ci: native iOS build */"
if marker in s:
    print("fex-native-fixes: already applied")
    sys.exit(0)
anchor = "#endif\n#endif\n\n#ifdef FEX_IOS_HOST\n/* ml648:"
if s.count(anchor) != 1:
    sys.exit(f"fex-native-fixes: anchor found {s.count(anchor)} times in {p}")
s = s.replace(anchor, "#endif\n#endif\n\n#ifndef FEX_IOS_HOST\n" + marker +
              "\nstatic uint64_t IosCbEntryLog[8] {};\nstatic uint64_t IosFfsBypassLog[4] {};\n#endif\n\n"
              "#ifdef FEX_IOS_HOST\n/* ml648:")
open(p, "w", encoding="utf-8", newline="").write(s)
print("fex-native-fixes: zeroed probe counters for the native build")
