"""CI: make the pinned FEX build as the native iOS library the app links (FEX/build-ios).

Diagnostics at the pinned commit that were only ever built into FEX's Windows-PE modules for the
iOS host (xtajit64.dll, xtajit.dll), so the native Mach-O build cannot compile or link them:
  * Core.cpp's probes ([ffs-bypass], [cb-entry]) read IosFfsBypassLog/IosCbEntryLog outside any
    #ifdef but declare them only under FEX_IOS_HOST (the PE modules' define, which also pulls in
    Win32 code). The native library gets zeroed counters: the reporters compare against values
    nothing increments, exactly as the WOW64 module's own fallback does.
  * Arm64.cpp's [caspal128] report describes the faulting region with VirtualQuery. Kept as is
    under _WIN32; the native build logs the same line without the region details.
Idempotent; run from the repository root.
"""
import sys

MARKER = "/* ci: native iOS build */"


def patch(path, anchor, replacement, what):
    s = open(path, encoding="utf-8", newline="").read()
    if replacement in s:
        print(f"fex-native-fixes: {what}: already applied")
        return
    if s.count(anchor) != 1:
        sys.exit(f"fex-native-fixes: {what}: anchor found {s.count(anchor)} times in {path}")
    open(path, "w", encoding="utf-8", newline="").write(s.replace(anchor, replacement))
    print(f"fex-native-fixes: {what}")


patch("FEX/FEXCore/Source/Interface/Core/Core.cpp",
      "#endif\n#endif\n\n#ifdef FEX_IOS_HOST\n/* ml648:",
      "#endif\n#endif\n\n#ifndef FEX_IOS_HOST\n" + MARKER +
      "\nstatic uint64_t IosCbEntryLog[8] {};\nstatic uint64_t IosFfsBypassLog[4] {};\n#endif\n\n"
      "#ifdef FEX_IOS_HOST\n/* ml648:",
      "Core.cpp: zeroed probe counters")

# CompileBlock's [rpm-cas] drain calls rpm_cas_snapshot_take, which lives in FEX's rpmalloc fork -
# and FEX builds no rpmalloc on Apple platforms. A weak "no snapshot" fallback; a linked rpmalloc's
# strong definition still wins.
patch("FEX/FEXCore/Source/Interface/Core/Core.cpp",
      "int rpm_cas_snapshot_take(struct rpm_cas_snapshot* out);\n}\n",
      "int rpm_cas_snapshot_take(struct rpm_cas_snapshot* out);\n}\n"
      "#ifndef FEX_IOS_HOST " + MARKER + "\n"
      "extern \"C\" __attribute__((weak)) int rpm_cas_snapshot_take(struct rpm_cas_snapshot*) {\n"
      "  return 0;\n}\n#endif\n",
      "Core.cpp: weak rpm_cas_snapshot_take")

CASPAL_WIN32 = """  MEMORY_BASIC_INFORMATION mbi {};
  const char* type = "?";
  if (VirtualQuery(reinterpret_cast<LPCVOID>(GPRs[AddressReg]), &mbi, sizeof(mbi))) {
    type = mbi.Type == MEM_IMAGE ? "MEM_IMAGE" : mbi.Type == MEM_MAPPED ? "MEM_MAPPED" : "MEM_PRIVATE";
  }
  LogMan::Msg::EFmt("[caspal128] MISALIGNED-UNSUPPORTED Size={} addrReg=x{} addr={:#x} misalign={} "
                    "crosses16B={} | region base={} size={:#x} prot={:#x} type={} state={:#x}",
                    Size, AddressReg, GPRs[AddressReg], GPRs[AddressReg] & 15,
                    (GPRs[AddressReg] & 15) ? "yes" : "no", mbi.BaseAddress, mbi.RegionSize,
                    mbi.Protect, type, mbi.State);
"""
# AllocatorHooks.cpp defines IOS_RPM_GUARD only in its ENABLE_FEX_ALLOCATOR branch, but the plain
# malloc_usable_size wrapper of the other branch uses it too (build/fex-ios/build.sh builds with
# ENABLE_FEX_ALLOCATOR=OFF, and the app links this object as libJemallocLibs.a).
patch("FEX/FEXCore/Source/Utils/AllocatorHooks.cpp",
      "  IOS_RPM_GUARD();\n#ifdef __APPLE__\n  return ::malloc_size(ptr);",
      "#ifdef IOS_RPM_GUARD " + MARKER + "\n  IOS_RPM_GUARD();\n#endif\n#ifdef __APPLE__\n  return ::malloc_size(ptr);",
      "AllocatorHooks.cpp: IOS_RPM_GUARD only where defined")

patch("FEX/FEXCore/Source/Utils/ArchHelpers/Arm64.cpp",
      CASPAL_WIN32,
      "#ifdef _WIN32\n" + CASPAL_WIN32 + "#else\n  " + MARKER + "\n"
      "  LogMan::Msg::EFmt(\"[caspal128] MISALIGNED-UNSUPPORTED Size={} addrReg=x{} addr={:#x} misalign={}\",\n"
      "                    Size, AddressReg, GPRs[AddressReg], GPRs[AddressReg] & 15);\n#endif\n",
      "Arm64.cpp: [caspal128] without VirtualQuery")
