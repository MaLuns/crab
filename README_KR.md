<div align="center">
  <img src="Shared/Resources/CrabIcon.png" width="128" alt="Crab 아이콘" />
  <h1>Crab</h1>
  <p><b>자주 쓰는 파일 작업을 Finder의 우클릭 메뉴에서</b></p>
  <p><a href="README.md">简体中文</a> · <a href="README_TW.md">繁體中文</a> · <a href="README_EN.md">English</a> · <a href="README_JA.md">日本語</a> · 한국어 · <a href="README_FR.md">Français</a> · <a href="README_ES.md">Español</a> · <a href="README_PT.md">Português</a> · <a href="README_DE.md">Deutsch</a></p>
  <p>macOS 13.0+</p>
</div>

![작업 라이브러리: 작업 검색, 필터링 및 관리 (중국어 간체 화면)](Previews/操作库.png)

<details>
<summary>메뉴 구성 보기</summary>

![메뉴 구성: 그룹과 메뉴 항목 관리 (중국어 간체 화면)](Previews/菜单编排.png)

</details>

## 특징

- **파일 도구**: 파일 생성, 경로 복사, 잘라내기와 붙여넣기, 파일 검증, 이미지 변환, ZIP / 7z 압축 및 압축 해제.
- **사용자 지정 작업**: 파일 템플릿, 복사·이동 대상 폴더, 자주 쓰는 폴더, 앱, 사용자 지정 아이콘과 스크립트 추가.
- **메뉴 구성**: 그룹 관리, 드래그로 순서 변경, 메뉴 항목별 이름·아이콘·표시 여부 설정.
- **외관과 언어**: 컬러 또는 단색 아이콘, 시스템 설정에 맞춤·라이트·다크 윈도우 테마, 9개 인터페이스 언어 지원.

## 시작하기

macOS 13 이상과 전체 Xcode 도구 모음이 필요합니다. 프로젝트 루트 디렉터리에서 빌드하고 실행합니다.

```sh
bash Scripts/build.sh
open build/Build/Products/Release/Crab.app
```

1. **일반 설정**의 권한 영역에서 확장 프로그램 관리를 열고 **Crab Finder 菜单**를 활성화합니다.
2. **작업 라이브러리**의 기본 작업을 사용하거나 **추가**를 클릭해 사용자 지정 작업을 추가합니다.
3. **메뉴 구성**에서 작업을 추가하고 그룹과 순서를 조정합니다. 새 작업은 메뉴에 자동으로 추가되지 않습니다.
4. Crab을 실행한 상태로 Finder로 돌아가 파일, 폴더 또는 빈 공간에서 우클릭 메뉴를 엽니다.

현재 빌드는 ad-hoc 서명을 사용하며 Apple 공증을 받지 않았습니다.

## 사용 안내

- 앱 항목을 사용하려면 해당 앱이 설치되어 있어야 합니다. 스크립트에는 사용 가능한 인터프리터가 필요하며, 원본 파일과 실행 권한은 변경하지 않습니다.
- 압축 해제는 ZIP / 7z를 지원하며 RAR이나 암호화된 압축 파일은 지원하지 않습니다. 크기 등의 제한은 [코덱 설명](Support/NativeCodecs.md)을 참고하세요.
- **숨김 파일 표시 / 숨김 파일 숨기기**는 Finder를 재시작합니다.
- iCloud 및 OneDrive 폴더의 보조 메뉴는 **일반 설정**에서 활성화하고 **손쉬운 사용**과 **Finder 자동화** 권한을 허용해야 합니다. **입력 모니터링**은 시스템 안내에 따라 허용하세요.

## 감사의 말

- **libwebp**: 무손실 WebP 인코딩 지원.
- **libarchive**: macOS 시스템 라이브러리를 통한 7z 디코딩 지원.

## 라이선스

[GPL](LICENSE)
