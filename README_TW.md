<div align="center">
  <img src="Shared/Resources/CrabIcon.png" width="128" alt="Crab 圖示" />
  <h1>Crab</h1>
  <p><b>把常用檔案操作，放進 Finder 右鍵選單</b></p>
  <p><a href="README.md">简体中文</a> · 繁體中文 · <a href="README_EN.md">English</a> · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · <a href="README_FR.md">Français</a> · <a href="README_ES.md">Español</a> · <a href="README_PT.md">Português</a> · <a href="README_DE.md">Deutsch</a></p>
  <p>macOS 13.0+</p>
</div>

![操作庫：搜尋、篩選並管理操作（簡體中文介面）](Previews/操作库.png)

<details>
<summary>查看選單編排</summary>

![選單編排：管理群組和選單項目（簡體中文介面）](Previews/菜单编排.png)

</details>

## 特點

- **檔案工具**：新增檔案、拷貝路徑、剪下貼上、檔案校驗、圖片轉換，以及 ZIP / 7z 壓縮解壓縮。
- **自訂操作**：加入檔案範本、傳送目標目錄、常用目錄、應用程式、自訂圖示和腳本。
- **選單編排**：管理群組、拖移排序，獨立調整選單項目的名稱、圖示和顯示狀態。
- **外觀與語言**：彩色或單色圖示，跟隨系統、淺色或深色視窗主題，支援九種介面語言。

## 開始使用

需要 macOS 13 或更新版本，以及完整的 Xcode 工具鏈。在專案根目錄建置並開啟：

```sh
bash Scripts/build.sh
open build/Build/Products/Release/Crab.app
```

1. 在「通用設置」的權限區域開啟延伸功能管理，啟用 **Crab Finder 菜单**。
2. 在「操作庫」使用預設操作，或點擊「新增」加入自訂操作。
3. 在「選單編排」加入操作，調整群組和順序。新增操作不會自動加入選單。
4. 保持 Crab 執行，回到 Finder，在檔案、目錄或空白位置開啟右鍵選單。

目前建置使用 ad-hoc 簽章，未經 Apple 公證。

## 使用提示

- 應用程式入口需要安裝對應的應用程式；腳本需要可用的直譯器，原始檔案及執行權限保持不變。
- 解壓縮支援 ZIP / 7z，不支援 RAR 或加密封存檔；大小等限制見[編解碼說明](Support/NativeCodecs.md)。
- 「顯示隱藏檔案 / 不顯示隱藏檔案」會重新啟動 Finder。
- iCloud 與 OneDrive 資料夾中的備用選單需在「通用設置」中啟用，並授予「輔助使用」和「Finder 自動化」權限；「輸入監控」依系統提示授權。

## 致謝

- **libwebp**：提供無損 WebP 編碼支援。
- **libarchive**：透過 macOS 系統函式庫提供 7z 解碼支援。

## 授權

遵循 [Crab Noncommercial Source License 1.0](LICENSE)。個人非商業使用免費；散布須免費公開完整對應原始碼，修改版沿用本授權條款；商業用途須事先取得書面授權。
