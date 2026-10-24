#!/bin/sh
# Regenerates faf/<arch>/: what FFmpeg's configure writes for faf-re's configuration
# (config.h, config_components.h, libavutil/avconfig.h, the component lists) plus
# libavutil/ffversion.h, and sources.cmake (the object list, from FFmpeg's Makefiles).
#
#   sh faf/generate.sh            both architectures
#   sh faf/generate.sh x64 x86    the ones named
#
# Runs in Git Bash or MSYS2 on Windows. Needs LLVM (clang-cl, lld-link, llvm-lib,
# llvm-nm; LLVM_ROOT, default C:/Program Files/LLVM), Visual Studio 2022 with the C++
# workload, a Windows 10/11 SDK and Python 3 (PYTHON, default python3 or python).
# No make: configure only writes files, and faf/gen_sources.py reads the Makefiles.
set -eu

FAF=$(cd "$(dirname "$0")" && pwd)
SRC=$(dirname "$FAF")

# The configuration (see README.md). FFmpeg's own build would need make; faf/CMakeLists.txt
# builds the static libraries from the generated object lists instead.
FAF_CONFIGURE_OPTIONS="--disable-x86asm --disable-everything --disable-programs --disable-doc --disable-network
--enable-static --disable-shared
--enable-avcodec --enable-avformat --enable-avutil --enable-swscale --enable-swresample
--enable-decoder=mpeg1video,mpeg2video,adpcm_adx,mp1,mp2,mp3
--enable-parser=mpegvideo,mpegaudio,adx
--enable-demuxer=mpegps,mpegvideo,adx,mp3
--enable-protocol=file"
FAF_LIBRARIES="avutil swresample swscale avcodec avformat"

LLVM_ROOT=${LLVM_ROOT:-C:/Program Files/LLVM}
PATH="$(cygpath -u "$LLVM_ROOT")/bin:$PATH"
export PATH
for tool in clang-cl lld-link llvm-lib llvm-nm; do
  command -v $tool >/dev/null || { echo "generate.sh: $tool not found under LLVM_ROOT=$LLVM_ROOT" >&2; exit 1; }
done
if [ -z "${PYTHON:-}" ]; then
  PYTHON=$(command -v python3 || command -v python || true)
fi
[ -n "$PYTHON" ] || { echo "generate.sh: no Python 3 (set PYTHON)" >&2; exit 1; }

# The MSVC toolset and Windows SDK, as INCLUDE and LIB for clang-cl and lld-link (what a
# Visual Studio developer prompt sets).
pf86=$(cygpath -u "${PROGRAMFILES:-C:/Program Files} (x86)")
vswhere="$pf86/Microsoft Visual Studio/Installer/vswhere.exe"
if [ -z "${VCToolsInstallDir:-}" ]; then
  vsroot=$("$vswhere" -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
           -property installationPath | tr -d '\r')
  vcver=$(tr -d '\r\n ' < "$(cygpath -u "$vsroot")/VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt")
  VCToolsInstallDir="$vsroot\\VC\\Tools\\MSVC\\$vcver"
fi
vctools=$(cygpath -m "$VCToolsInstallDir")
sdkroot=$(cygpath -m "${WindowsSdkDir:-$pf86/Windows Kits/10}")
if [ -z "${WindowsSDKVersion:-}" ]; then
  WindowsSDKVersion=$(cd "$sdkroot/Include" && for v in 10.*; do [ -f "$v/um/windows.h" ] && echo "$v"; done | sort -V | tail -1)
fi
sdkver=${WindowsSDKVersion%\\}
sdkver=${sdkver%/}
echo "generate.sh: MSVC $vctools, Windows SDK $sdkroot $sdkver"

generate() {
  arch=$1
  case $arch in
    x64) ffarch=x86_64; triple=x86_64-pc-windows-msvc; libdir=x64 ;;
    x86) ffarch=x86;    triple=i686-pc-windows-msvc;   libdir=x86 ;;
    *) echo "generate.sh: unknown architecture $arch (x64 or x86)" >&2; exit 1 ;;
  esac
  out="$FAF/$arch"
  build=$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-faf-$arch.XXXXXX")

  INCLUDE="$vctools/include;$sdkroot/Include/$sdkver/ucrt;$sdkroot/Include/$sdkver/um;$sdkroot/Include/$sdkver/shared"
  LIB="$vctools/lib/$libdir;$sdkroot/Lib/$sdkver/ucrt/$libdir;$sdkroot/Lib/$sdkver/um/$libdir"
  export INCLUDE LIB

  echo "generate.sh: configuring $arch in $build"
  # The toolchain options. --disable-debug: debug information is the CMake build's
  # choice, and configure's default (--enable-debug) adds -Oy- on x86 after it has
  # found EBP free for inline assembly, which clang-cl then cannot compile.
  # shellcheck disable=SC2086
  (cd "$build" && "$SRC/configure" \
      --toolchain=msvc --cc=clang-cl --cxx=clang-cl --ld=lld-link --ar=llvm-lib --nm=llvm-nm \
      --target-os=win32 --arch=$ffarch --extra-cflags=--target=$triple --disable-debug \
      $FAF_CONFIGURE_OPTIONS) > "$build/configure.out" 2>&1 || {
    tail -40 "$build/ffbuild/config.log" >&2; echo "generate.sh: configure failed, see $build" >&2; exit 1; }

  rm -rf "$out"
  mkdir -p "$out/libavutil"
  cp "$build/config.h" "$build/config_components.h" "$out/"
  cp "$build/libavutil/avconfig.h" "$out/libavutil/"
  # What FFmpeg's Makefile generates before compiling (libavutil/ffversion.h).
  (cd "$build" && sh "$SRC/ffbuild/version.sh" "$SRC" libavutil/ffversion.h)
  cp "$build/libavutil/ffversion.h" "$out/libavutil/"
  for lib in $FAF_LIBRARIES; do
    for list in "$build/lib$lib"/*_list.c; do
      [ -f "$list" ] || continue
      mkdir -p "$out/lib$lib"
      cp "$list" "$out/lib$lib/"
    done
  done
  "$PYTHON" "$FAF/gen_sources.py" "$SRC" "$build/ffbuild/config.mak" "$out/sources.cmake" $FAF_LIBRARIES

  # configure writes CRLF-free text; keep the build dir only on failure.
  rm -rf "$build"
  echo "generate.sh: wrote $out"
}

if [ $# -eq 0 ]; then
  set -- x64 x86
fi
for arch in "$@"; do
  generate "$arch"
done
