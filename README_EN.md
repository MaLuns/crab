<div align="center">
  <img src="Shared/Resources/CrabIcon.png" width="128" alt="Crab icon" />
  <h1>Crab</h1>
  <p><b>Your everyday file tools, right in Finder’s context menu</b></p>
  <p><a href="README.md">简体中文</a> · <a href="README_TW.md">繁體中文</a> · English · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · <a href="README_FR.md">Français</a> · <a href="README_ES.md">Español</a> · <a href="README_PT.md">Português</a> · <a href="README_DE.md">Deutsch</a></p>
  <p>macOS 13.0+</p>
</div>

![Operation Library: search, filter, and manage operations (Simplified Chinese interface)](Previews/操作库.png)

<details>
<summary>View Menu Layout</summary>

![Menu Layout: manage groups and menu items (Simplified Chinese interface)](Previews/菜单编排.png)

</details>

## Features

- **File tools**: Create files, copy paths, cut and paste, verify files, convert images, and compress or extract ZIP / 7z archives.
- **Custom operations**: Add file templates, copy or move destinations, favorite folders, applications, custom icons, and scripts.
- **Menu layout**: Organize groups, reorder by dragging, and customize each menu item’s name, icon, and visibility.
- **Appearance and languages**: Color or monochrome icons, system, light, or dark window themes, and nine interface languages.

## Getting Started

Requires macOS 13 or later and the full Xcode toolchain. Build and open the app from the project root:

```sh
bash Scripts/build.sh
open build/Build/Products/Release/Crab.app
```

1. In the permissions section of **General**, open extension management and enable **Crab Finder 菜单**.
2. Use the presets in **Operation Library**, or click **Add** to add custom operations.
3. Add operations in **Menu Layout** and arrange their groups and order. New operations are not added to the menu automatically.
4. Keep Crab running, return to Finder, and open the context menu on a file, folder, or empty space.

The current build uses ad-hoc signing and is not notarized by Apple.

## Usage Notes

- Application entries require the corresponding apps to be installed. Scripts require an available interpreter; their original files and execution permissions are left unchanged.
- Extraction supports ZIP / 7z, but not RAR or encrypted archives. See the [codec notes](Support/NativeCodecs.md) for size and other limits.
- **Show Hidden Files / Hide Hidden Files** restarts Finder.
- Enable the fallback menu for iCloud and OneDrive folders in **General**, then grant Accessibility and Finder Automation permissions. Grant Input Monitoring when prompted by the system.

## Acknowledgments

- **libwebp**: Lossless WebP encoding.
- **libarchive**: 7z decoding through the macOS system library.

## License

[GPL](LICENSE)
