<div align="center">
  <img src="Shared/Resources/CrabIcon.png" width="128" alt="Crab アイコン" />
  <h1>Crab</h1>
  <p><b>いつものファイル操作を、Finder のコンテキストメニューに</b></p>
  <p><a href="README.md">简体中文</a> · <a href="README_TW.md">繁體中文</a> · <a href="README_EN.md">English</a> · 日本語 · <a href="README_KR.md">한국어</a> · <a href="README_FR.md">Français</a> · <a href="README_ES.md">Español</a> · <a href="README_PT.md">Português</a> · <a href="README_DE.md">Deutsch</a></p>
  <p>macOS 13.0+</p>
</div>

![操作ライブラリ：操作の検索、絞り込み、管理（簡体字中国語の画面）](Previews/操作库.png)

<details>
<summary>メニュー構成を見る</summary>

![メニュー構成：グループとメニュー項目の管理（簡体字中国語の画面）](Previews/菜单编排.png)

</details>

## 特長

- **ファイルツール**：ファイル作成、パスのコピー、カット＆ペースト、ファイル検証、画像変換、ZIP / 7z の圧縮・展開。
- **カスタム操作**：ファイルテンプレート、コピー・移動先、よく使うフォルダ、アプリ、カスタムアイコン、スクリプトを追加。
- **メニュー構成**：グループ管理、ドラッグでの並べ替え、メニュー項目ごとの名前・アイコン・表示状態の設定。
- **外観と言語**：カラー・モノクロのアイコン、システムに合わせる・ライト・ダークのウインドウテーマ、9 種類の表示言語。

## 使い始める

macOS 13 以降と、完全な Xcode ツールチェーンが必要です。プロジェクトのルートディレクトリでビルドし、起動します。

```sh
bash Scripts/build.sh
open build/Build/Products/Release/Crab.app
```

1. 「一般設定」の権限欄から機能拡張の管理を開き、**Crab Finder 菜单** を有効にします。
2. 「操作ライブラリ」の既定の操作を使うか、「追加」をクリックしてカスタム操作を追加します。
3. 「メニュー構成」で操作を追加し、グループと順序を調整します。新しい操作はメニューに自動追加されません。
4. Crab を起動したまま Finder に戻り、ファイル、フォルダ、または空白部分でコンテキストメニューを開きます。

現在のビルドは ad-hoc 署名を使用しており、Apple の公証は受けていません。

## 利用上の注意

- アプリの項目には対応するアプリのインストールが必要です。スクリプトには利用可能なインタープリターが必要で、元のファイルや実行権限は変更しません。
- 展開は ZIP / 7z に対応し、RAR や暗号化アーカイブには対応していません。サイズなどの制限は[コーデックの説明](Support/NativeCodecs.md)を参照してください。
- 「隠しファイルを表示 / 隠しファイルを非表示」は Finder を再起動します。
- iCloud と OneDrive のフォルダで代替メニューを使うには、「一般設定」で有効にし、「アクセシビリティ」と「Finder のオートメーション」を許可してください。「入力監視」はシステムの案内に従って許可します。

## 謝辞

- **libwebp**：可逆 WebP エンコード。
- **libarchive**：macOS のシステムライブラリによる 7z デコード。

## ライセンス

[GPL](LICENSE)
