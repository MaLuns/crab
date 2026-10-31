<div align="center">
  <img src="Shared/Resources/CrabIcon.png" width="128" alt="Icône de Crab" />
  <h1>Crab</h1>
  <p><b>Vos opérations courantes sur les fichiers, dans le menu contextuel du Finder</b></p>
  <p><a href="README.md">简体中文</a> · <a href="README_TW.md">繁體中文</a> · <a href="README_EN.md">English</a> · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · Français · <a href="README_ES.md">Español</a> · <a href="README_PT.md">Português</a> · <a href="README_DE.md">Deutsch</a></p>
  <p>macOS 13.0+</p>
</div>

![Bibliothèque : rechercher, filtrer et gérer les opérations — interface en chinois simplifié](Previews/操作库.png)

<details>
<summary>Voir la disposition des menus</summary>

![Menus : organiser les groupes et les éléments du menu — interface en chinois simplifié](Previews/菜单编排.png)

</details>

## Fonctionnalités

- **Outils pour les fichiers** : création de fichiers, copie de chemins, couper-coller, vérification de fichiers, conversion d’images, compression et extraction ZIP / 7z.
- **Opérations personnalisées** : ajoutez des modèles de fichiers, des dossiers de destination, des dossiers favoris, des applications, des icônes personnalisées et des scripts.
- **Disposition des menus** : organisez les groupes par glisser-déposer et ajustez séparément le nom, l’icône et la visibilité de chaque élément.
- **Apparence et langues** : icônes en couleur ou monochromes, fenêtres suivant le thème du système ou utilisant un thème clair ou sombre, et neuf langues d’interface.

## Prise en main

Crab nécessite macOS 13 ou une version ultérieure, ainsi que la chaîne d’outils Xcode complète pour la compilation. Depuis la racine du projet, compilez puis ouvrez l’application :

```sh
bash Scripts/build.sh
open build/Build/Products/Release/Crab.app
```

1. Dans la section des autorisations de « Général », ouvrez la gestion des extensions et activez **Crab Finder 菜单**.
2. Utilisez les opérations prédéfinies dans « Bibliothèque » ou cliquez sur « Ajouter » pour en ajouter des personnalisées.
3. Dans « Menus », ajoutez les opérations et ajustez les groupes et leur ordre. Une nouvelle opération n’est pas ajoutée automatiquement au menu.
4. Laissez Crab ouvert, revenez dans le Finder et ouvrez le menu contextuel d’un fichier, d’un dossier ou d’un espace vide.

La compilation actuelle utilise une signature ad hoc et n’est pas notariée par Apple.

## À savoir

- Les raccourcis vers les applications nécessitent que celles-ci soient installées. Les scripts nécessitent un interpréteur disponible ; leur contenu et leurs autorisations d’exécution restent inchangés.
- L’extraction prend en charge ZIP / 7z, mais pas RAR ni les archives chiffrées. Les limites de taille et autres restrictions sont décrites dans les [notes sur les codecs](Support/NativeCodecs.md).
- « Afficher les fichiers masqués / Ne pas afficher les fichiers masqués » redémarre le Finder.
- Le menu alternatif pour les dossiers iCloud et OneDrive doit être activé dans « Général » et nécessite les autorisations Accessibilité et Automatisation du Finder. Accordez la Surveillance de l’entrée lorsque le système le demande.

## Remerciements

- **libwebp** : encodage WebP sans perte.
- **libarchive** : décodage 7z via la bibliothèque système de macOS.

## Licence

[GPL](LICENSE)
