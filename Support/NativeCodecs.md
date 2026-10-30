# Archive and WebP integration

`ArchiveTools.compress7z(_:in:)` writes an actual 7z container through macOS `/usr/bin/tar --format=7zip`. `ArchiveTools.extractArchive(_:in:)` accepts ZIP and 7z by signature. ZIP retains the existing strict central/local-header parser; 7z uses the system libarchive streaming API. RAR and encrypted archives are not accepted. Neither API overwrites an existing destination.

Extraction snapshots the input into a private staging directory, rejects links and special entries, absolute/traversing/duplicate paths and size overruns, and commits only after the reader has consumed every file and completed its checks. Limits: 2 GiB input, 10,000 entries, 1 GiB per file, 2 GiB total output. All failures remove staging. ZIP verifies its CRC directly; the 7z reader reports libarchive data/CRC errors. Permissions on newly extracted files/directories are 0600/0700.

`MediaTools.convert(_:format: .webp)` uses the official libwebp 1.6.0 lossless RGBA encoder, with straight-alpha conversion from Core Graphics and a 16383-pixel WebP dimension limit. Existing image limits and batch rollback remain in force.

## Offline build

Complete official source is in `Vendor/libwebp`, including COPYING and PATENTS. The source URL, commit and archive SHA-256 are recorded in `Support/WebP/SOURCE.json`.

Run `bash Support/WebP/build.sh`. With `ARCHS="arm64 x86_64"` (default), this creates universal `Support/WebP/lib/libwebp.a`; either architecture can also be selected alone. It requires the Xcode command line toolchain and performs no downloads or Homebrew calls. The static archive includes libsharpyuv. All C objects target macOS 13. Both architectures have been linked locally, and the arm64 encoder version probe ran successfully. There are no third-party dynamic-library dependencies.

The app needs a prebuild invocation of this script, Swift include paths `$(SRCROOT)/Support/CArchive` and `$(SRCROOT)/Support/WebP`, library search path `$(SRCROOT)/Support/WebP/lib`, and linker flags `-larchive -lwebp`. The test target also needs the module include paths. Include `Support/WebP/COPYING` and `Support/WebP/PATENTS` with the distributed app's license resources. The Finder extension does not use these codecs.

CArchive contains unchanged public libarchive 3.7.4 headers from the official tag, including their complete BSD notices. Their checksums and the specific runtime symbols used are recorded in `Support/CArchive/SOURCE.json`. The production reader uses long-established libarchive 3.x APIs (including 7zip, UTF-8 paths, encryption flags, size and sparse entry queries), rather than the newer disk extraction APIs. The module links Apple's system libarchive. Current-machine execution reports libarchive 3.7.4; macOS 13 is the compilation target, not an OS on which this machine ran the tests.

`Tests/ArchiveAndWebPTests.swift` adds real 7z/WebP roundtrips and malicious archive/rollback tests. The declared-size test builds valid 7z metadata with correct header CRCs and a >1 GiB declaration, allowing the limit to be tested without expanding data.
