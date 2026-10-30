<div align="center">
  <img src="Shared/Resources/CrabIcon.png" width="128" alt="Crab-Symbol" />
  <h1>Crab</h1>
  <p><b>Häufige Dateiaktionen direkt im Kontextmenü des Finders</b></p>
  <p><a href="README.md">简体中文</a> · <a href="README_TW.md">繁體中文</a> · <a href="README_EN.md">English</a> · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · <a href="README_FR.md">Français</a> · <a href="README_ES.md">Español</a> · <a href="README_PT.md">Português</a> · Deutsch</p>
  <p>macOS 13.0+</p>
</div>

![Aktionsbibliothek: Aktionen suchen, filtern und verwalten – Oberfläche auf vereinfachtem Chinesisch](Previews/操作库.png)

<details>
<summary>Menügestaltung ansehen</summary>

![Menügestaltung: Gruppen und Menüeinträge verwalten – Oberfläche auf vereinfachtem Chinesisch](Previews/菜单编排.png)

</details>

## Funktionen

- **Dateiwerkzeuge**: Dateien erstellen, Pfade kopieren, ausschneiden und einfügen, Dateien prüfen, Bilder konvertieren sowie ZIP / 7z komprimieren und entpacken.
- **Eigene Aktionen**: Dateivorlagen, Zielordner, häufig verwendete Ordner, Apps, eigene Symbole und Skripte hinzufügen.
- **Menügestaltung**: Gruppen verwalten, Einträge durch Ziehen umsortieren und Namen, Symbole und Sichtbarkeit für jeden Menüeintrag einzeln festlegen.
- **Darstellung und Sprachen**: farbige oder einfarbige Symbole, Fenster im Systemdesign oder mit hellem oder dunklem Design sowie neun Oberflächensprachen.

## Erste Schritte

Erforderlich sind macOS 13 oder neuer und zum Kompilieren die vollständige Xcode-Werkzeugkette. Im Projektverzeichnis kompilieren und öffnen:

```sh
bash Scripts/build.sh
open build/Build/Products/Release/Crab.app
```

1. Im Berechtigungsbereich unter „Allgemein“ die Erweiterungsverwaltung öffnen und **Crab Finder 菜单** aktivieren.
2. In der „Aktionsbibliothek“ die vorgegebenen Aktionen verwenden oder über „Hinzufügen“ eigene Aktionen ergänzen.
3. Unter „Menügestaltung“ Aktionen hinzufügen sowie Gruppen und Reihenfolge anpassen. Neue Aktionen werden nicht automatisch ins Menü aufgenommen.
4. Crab weiterlaufen lassen, zum Finder zurückkehren und das Kontextmenü einer Datei, eines Ordners oder einer freien Fläche öffnen.

Der aktuelle Build verwendet eine Ad-hoc-Signatur und ist nicht von Apple notarisiert.

## Hinweise zur Nutzung

- App-Verknüpfungen setzen die jeweilige installierte App voraus. Skripte benötigen einen verfügbaren Interpreter; ihr Inhalt und ihre Ausführungsrechte bleiben unverändert.
- Das Entpacken unterstützt ZIP / 7z, jedoch keine RAR-Dateien oder verschlüsselten Archive. Größenlimits und weitere Einschränkungen stehen in den [Codec-Hinweisen](Support/NativeCodecs.md).
- „Versteckte Dateien anzeigen / Versteckte Dateien ausblenden“ startet den Finder neu.
- Das alternative Menü für iCloud- und OneDrive-Ordner muss unter „Allgemein“ aktiviert werden und benötigt die Berechtigungen für Bedienungshilfen und Finder-Automation. Die Eingabeüberwachung wird bei Aufforderung durch das System freigegeben.

## Danksagung

- **libwebp**: verlustfreie WebP-Kodierung.
- **libarchive**: 7z-Dekodierung über die macOS-Systembibliothek.

## Lizenz

Es gilt die [Crab Noncommercial Source License 1.0](LICENSE). Die persönliche, nicht kommerzielle Nutzung ist kostenlos. Jede Weitergabe muss kostenlos erfolgen und den vollständigen zugehörigen Quellcode öffentlich bereitstellen; geänderte Versionen bleiben unter dieser Lizenz. Eine kommerzielle Nutzung erfordert eine vorherige schriftliche Genehmigung.
