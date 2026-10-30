<div align="center">
  <img src="Shared/Resources/CrabIcon.png" width="128" alt="Icono de Crab" />
  <h1>Crab</h1>
  <p><b>Tus operaciones habituales con archivos, en el menú contextual de Finder</b></p>
  <p><a href="README.md">简体中文</a> · <a href="README_TW.md">繁體中文</a> · <a href="README_EN.md">English</a> · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · <a href="README_FR.md">Français</a> · Español · <a href="README_PT.md">Português</a> · <a href="README_DE.md">Deutsch</a></p>
  <p>macOS 13.0+</p>
</div>

![Biblioteca: buscar, filtrar y gestionar operaciones; interfaz en chino simplificado](Previews/操作库.png)

<details>
<summary>Ver el diseño del menú</summary>

![Diseño del menú: organizar grupos y elementos; interfaz en chino simplificado](Previews/菜单编排.png)

</details>

## Características

- **Herramientas de archivos**: crear archivos, copiar rutas, cortar y pegar, comprobar archivos, convertir imágenes, y comprimir y extraer ZIP / 7z.
- **Operaciones personalizadas**: añade plantillas de archivos, carpetas de destino, carpetas favoritas, aplicaciones, iconos personalizados y scripts.
- **Diseño del menú**: organiza grupos, cambia el orden arrastrando y ajusta por separado el nombre, el icono y la visibilidad de cada elemento.
- **Apariencia e idiomas**: iconos en color o monocromos, ventanas con el tema del sistema, claro u oscuro, y nueve idiomas de interfaz.

## Primeros pasos

Se requiere macOS 13 o posterior y la cadena de herramientas completa de Xcode para compilar. Desde la raíz del proyecto, compila y abre la aplicación:

```sh
bash Scripts/build.sh
open build/Build/Products/Release/Crab.app
```

1. En la sección de permisos de «General», abre la gestión de extensiones y activa **Crab Finder 菜单**.
2. Utiliza las operaciones predefinidas de «Biblioteca» o pulsa «Añadir» para agregar operaciones personalizadas.
3. En «Diseño del menú», añade operaciones y ajusta los grupos y su orden. Las operaciones nuevas no se añaden automáticamente al menú.
4. Mantén Crab en ejecución, vuelve a Finder y abre el menú contextual de un archivo, una carpeta o un espacio vacío.

La compilación actual utiliza una firma ad hoc y no está notarizada por Apple.

## Notas de uso

- Los accesos a aplicaciones requieren que estas estén instaladas. Los scripts necesitan un intérprete disponible; su contenido y sus permisos de ejecución permanecen intactos.
- La extracción admite ZIP / 7z, pero no RAR ni archivos cifrados. Consulta los límites de tamaño y otras restricciones en las [notas sobre los códecs](Support/NativeCodecs.md).
- «Mostrar archivos ocultos / Ocultar archivos ocultos» reinicia Finder.
- El menú alternativo para carpetas de iCloud y OneDrive debe activarse en «General» y requiere permisos de Accesibilidad y Automatización de Finder. Concede la Monitorización de entrada cuando lo solicite el sistema.

## Agradecimientos

- **libwebp**: codificación WebP sin pérdida.
- **libarchive**: decodificación 7z mediante la biblioteca del sistema de macOS.

## Licencia

Crab se distribuye bajo la [Crab Noncommercial Source License 1.0](LICENSE). El uso personal no comercial es gratuito. Toda redistribución debe ser gratuita y publicar el código fuente correspondiente completo; las versiones modificadas mantienen esta licencia. El uso comercial requiere autorización previa por escrito.
