# FFmpeg for faf-re

This repository is the source of FFmpeg that [faf-re](https://github.com/Draiget/faf-re) builds and links statically for its SFD movie player. It holds the official [FFmpeg](https://ffmpeg.org) 7.1.3 release, unmodified, plus a `faf/` folder with a CMake build of the libraries faf-re needs. It contains no binaries.

## Contents

- Everything outside `faf/`, `.gitattributes` and `.github/` is the official release tarball `ffmpeg-7.1.3.tar.xz` (SHA256 `f0bf043299db9e3caacb435a712fc541fbb07df613c4b893e8b77e67baf3adbe`), byte for byte, in the first commit. FFmpeg's files are never edited here; the top-level `README.md` is FFmpeg's own, this page is `.github/README.md`.
- `faf/CMakeLists.txt` builds avutil, swresample, swscale, avcodec and avformat as static libraries with clang-cl, for x64 or x86 (chosen by the compiler's pointer size).
- `faf/x64/` and `faf/x86/` hold what FFmpeg's `configure` generates for this configuration (`config.h`, `config_components.h`, `libavutil/avconfig.h`, and the component lists `libavcodec/codec_list.c`, `parser_list.c`, `bsf_list.c`, `libavformat/demuxer_list.c`, `muxer_list.c`, `protocol_list.c`), `libavutil/ffversion.h` (made by `ffbuild/version.sh`, as FFmpeg's Makefile does), and `sources.cmake`: the source files of each library, the system libraries they need, and FFmpeg's preprocessor and compiler flags.
- `faf/generate.sh` regenerates both folders; `faf/gen_sources.py` writes `sources.cmake`.
- `.gitattributes` (`* -text`) keeps every file's bytes as committed, whatever the client's `core.autocrlf`.
- `.github/CODEOWNERS` makes every change need the repository owner's approval.

## Configuration

Only what the movie player needs: MPEG-PS demuxing, MPEG-1/2 video, ADX and MPEG-1/2 layer I-III audio, scaling and resampling. No GPL or nonfree component is enabled.

```
--disable-x86asm --disable-everything --disable-programs --disable-doc --disable-network
--enable-static --disable-shared
--enable-avcodec --enable-avformat --enable-avutil --enable-swscale --enable-swresample
--enable-decoder=mpeg1video,mpeg2video,adpcm_adx,mp1,mp2,mp3
--enable-parser=mpegvideo,mpegaudio,adx
--enable-demuxer=mpegps,mpegvideo,adx,mp3
--enable-protocol=file
```

This is faf-re's former DLL configuration with `--enable-static --disable-shared` in place of `--enable-shared --disable-static`, so the same components are built into static libraries.

The toolchain options `generate.sh` adds: `--toolchain=msvc --cc=clang-cl --cxx=clang-cl --ld=lld-link --ar=llvm-lib --nm=llvm-nm --target-os=win32 --arch=x86_64|x86 --extra-cflags=--target=x86_64-pc-windows-msvc|i686-pc-windows-msvc --disable-debug`. `--disable-debug` leaves debug information to the CMake build; configure's default would add `-Oy-` on x86 after deciding EBP is free for inline assembly, and clang-cl then cannot compile `libswscale/x86/rgb2rgb.c`.

Every library is compiled with FFmpeg's own flags from `config.mak` (including `-O2` in every configuration, since FFmpeg relies on dead-code elimination of disabled components), with `-DHAVE_AV_CONFIG_H -DBUILDING_<lib>` as `ffbuild/library.mak` adds them, and with the include path `faf/<arch>`, the source root, then configure's own (`compat/stdbit`). The C runtime follows the parent project's `CMAKE_MSVC_RUNTIME_LIBRARY` (static `/MT` when `faf/` is built on its own).

## Using it

```cmake
add_subdirectory(path/to/ffmpeg-mirror/faf ffmpeg)
target_link_libraries(app PRIVATE FFmpeg::FFmpeg)
```

`FFmpeg::FFmpeg` is an `INTERFACE` target with the public include directories (the source root and a generated folder holding `libavutil/avconfig.h`) and the five libraries with their system libraries (`user32`, `bcrypt`, `ole32`). The library targets are `ffmpeg_avutil`, `ffmpeg_swresample`, `ffmpeg_swscale`, `ffmpeg_avcodec` and `ffmpeg_avformat`; `FFMPEG_FAF_LIBRARIES` lists them in the parent scope so a parent project can add its own options. The configuration headers were generated for clang-cl; other compilers are refused.

## Regenerating

Run `sh faf/generate.sh` (or `sh faf/generate.sh x64` / `x86`) from Git Bash or MSYS2 on Windows. It needs LLVM (`clang-cl`, `lld-link`, `llvm-lib`, `llvm-nm`; `LLVM_ROOT`, default `C:/Program Files/LLVM`), Visual Studio 2022 with the C++ workload, a Windows 10/11 SDK and Python 3 (`PYTHON`). No `make` is needed.

For each architecture it runs FFmpeg's `configure` once in a temporary folder, with `INCLUDE` and `LIB` set to the MSVC toolset and Windows SDK, copies the generated files into `faf/<arch>/`, runs `ffbuild/version.sh` for `libavutil/ffversion.h`, and runs `gen_sources.py`.

`gen_sources.py` takes the object lists from FFmpeg's own Makefiles. It evaluates the part of them that decides what is compiled, with a small interpreter for the subset of make they use (both variable flavours, `+=`, `?=`, substitution references, `sort`/`filter`/`addprefix`-style functions, `ifdef`/`ifeq` conditionals and includes), on top of configure's `ffbuild/config.mak`. Per library it follows the top-level Makefile's `DOSUBDIR` and `ffbuild/library.mak`: `lib<name>/Makefile`, `lib<name>/$(ARCH)/Makefile`, `lib<name>/$(INTRINSICS)/Makefile`, `ffbuild/arch.mak`, then `OBJS += $(OBJS-yes)` and so on; the static library is `$(OBJS) $(STLIBOBJS)`. Target-specific `CFLAGS`/`CPPFLAGS` on objects are carried over as per-source options. For 7.1.3 its lists were checked against GNU make's own (the prerequisites of each `lib<name>.a` in `make -p`): identical for all five libraries on both architectures.

For a new FFmpeg version: replace the tree outside `faf/` with the new release tarball in its own commit, adjust the options in `generate.sh` if needed, regenerate and rebuild.

## License

FFmpeg is licensed under the GNU Lesser General Public License version 2.1 or later; see [`LICENSE.md`](../LICENSE.md) and [`COPYING.LGPLv2.1`](../COPYING.LGPLv2.1), FFmpeg's own files. This configuration enables no GPL or nonfree part, so the libraries are LGPL v2.1+. The files in `faf/` and `.github/` are under the same licence.

faf-re links these libraries statically. LGPL v2.1 section 6 permits that when the user can relink the application with a modified library: faf-re's complete source is public, so the engine can be rebuilt against a changed FFmpeg from this repository (or any other compatible one).
