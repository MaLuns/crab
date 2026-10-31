<div align="center">
  <img src="Shared/Resources/CrabIcon.png" width="128" alt="Ícone do Crab" />
  <h1>Crab</h1>
  <p><b>As operações de ficheiros do dia a dia, no menu de contexto do Finder</b></p>
  <p><a href="README.md">简体中文</a> · <a href="README_TW.md">繁體中文</a> · <a href="README_EN.md">English</a> · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · <a href="README_FR.md">Français</a> · <a href="README_ES.md">Español</a> · Português · <a href="README_DE.md">Deutsch</a></p>
  <p>macOS 13.0+</p>
</div>

![Biblioteca: pesquisar, filtrar e gerir operações; interface em chinês simplificado](Previews/操作库.png)

<details>
<summary>Ver a organização do menu</summary>

![Organizar menu: gerir grupos e itens do menu; interface em chinês simplificado](Previews/菜单编排.png)

</details>

## Funcionalidades

- **Ferramentas de ficheiros**: criar ficheiros, copiar caminhos, cortar e colar, verificar ficheiros, converter imagens e comprimir e extrair ZIP / 7z.
- **Operações personalizadas**: adicione modelos de ficheiros, pastas de destino, pastas favoritas, aplicações, ícones personalizados e scripts.
- **Organização do menu**: organize grupos, altere a ordem por arrastamento e ajuste separadamente o nome, o ícone e a visibilidade de cada item.
- **Aspeto e idiomas**: ícones a cores ou monocromáticos, janelas com o tema do sistema, claro ou escuro, e nove idiomas de interface.

## Primeiros passos

É necessário o macOS 13 ou posterior e o conjunto completo de ferramentas do Xcode para compilar. Na raiz do projeto, compile e abra a aplicação:

```sh
bash Scripts/build.sh
open build/Build/Products/Release/Crab.app
```

1. Na secção de permissões de «Geral», abra a gestão de extensões e ative **Crab Finder 菜单**.
2. Utilize as operações predefinidas da «Biblioteca» ou clique em «Adicionar» para acrescentar operações personalizadas.
3. Em «Organizar menu», adicione operações e ajuste os grupos e a respetiva ordem. As novas operações não são adicionadas automaticamente ao menu.
4. Mantenha o Crab em execução, volte ao Finder e abra o menu de contexto de um ficheiro, de uma pasta ou de uma área vazia.

A compilação atual utiliza uma assinatura ad hoc e não está notarizada pela Apple.

## Notas de utilização

- Os atalhos para aplicações exigem que estas estejam instaladas. Os scripts precisam de um interpretador disponível; o seu conteúdo e as suas permissões de execução mantêm-se inalterados.
- A extração suporta ZIP / 7z, mas não RAR nem arquivos encriptados. Consulte os limites de tamanho e outras restrições nas [notas sobre os codecs](Support/NativeCodecs.md).
- «Mostrar ficheiros ocultos / Ocultar ficheiros ocultos» reinicia o Finder.
- O menu alternativo para pastas do iCloud e do OneDrive tem de ser ativado em «Geral» e requer permissões de Acessibilidade e Automatização do Finder. Autorize a Monitorização de entrada quando o sistema o solicitar.

## Agradecimentos

- **libwebp**: codificação WebP sem perdas.
- **libarchive**: descodificação 7z através da biblioteca de sistema do macOS.

## Licença

[GPL](LICENSE)
