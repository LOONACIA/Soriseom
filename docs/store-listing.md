# Store 등록 문구 초안

2026-11-04 기준 Partner Center 문서의 제한을 따르는 초안입니다.

## 제출 전 확인

- [ ] Windows 10 실제 동작을 확인합니다. 매니페스트 최소 버전이 10.0.17763이라 Store가 Windows 10에도 제공하지만, 팝업 투명 처리와 Acrylic은 Windows 11에서만 확인했습니다([ARCHITECTURE.md의 구현 전에 확인할 것](ARCHITECTURE.md#구현-전에-확인할-것)).
- [ ] Description에 적은 Spotify와 YouTube Music을 실제 앱에서 확인합니다. 확인하지 못한 이름은 두 언어의 Description에서 뺍니다.
- [ ] 앨범아트 로드, 트레이 오른쪽 클릭 메뉴와 종료, Windows 모드 전환을 사람이 확인합니다([ADR-010](ADR.md#adr-010-release는-트리밍을-유지하고-il2104만-오류에서-뺀다)).
- [x] `PRIVACY.md`가 `main`에 머지되어 아래 Privacy policy URL이 열리는지 확인합니다.
- [ ] 업로드할 패키지로 Windows App Certification Kit을 돌립니다. 이 PC의 빌드와 Store 인증 결과가 다를 수 있습니다.

## 최초 제출 순서

1. Partner Center의 앱 ID 페이지에서 Package/Identity/Name, Package/Identity/Publisher, Package/Properties/PublisherDisplayName 값을 확인해 GitHub Secrets에 넣습니다.
   `gh secret set PACKAGE_IDENTITY_NAME`, `gh secret set PACKAGE_PUBLISHER`, `gh secret set PACKAGE_PUBLISHER_DISPLAY_NAME`
2. 패키지를 만듭니다. `gh workflow run store-release.yml -f version=1.0.0`
3. 실행이 끝나면 패키지를 내려받습니다. `gh run download <실행 ID> -n store-package`
4. Partner Center의 Packages 페이지에 `.msixupload`를 올립니다. 기기군 선택이 나오면 Windows 10/11 Desktop만 남깁니다.
5. Store listings, Properties, Age ratings, Submission options를 이 문서대로 채우고 언어별 스크린샷을 올립니다.
6. 제출합니다. 인증을 통과해 게시되기 전까지는 태그를 push하지 않습니다. 자동 제출은 이미 게시된 앱에만 쓸 수 있어 제출 단계에서 실패합니다.
7. 게시된 뒤부터는 최초 제출보다 높은 버전으로 `git tag vX.Y.Z`, `git push origin vX.Y.Z`를 실행합니다(ADR-007). 첫 태그 제출이 Secrets 인증을 처음 시험하는 때이므로 결과를 확인합니다.

## 공통 입력값

| 필드 | 입력값 | 사유 및 안내 |
|---|---|---|
| 주 카테고리 | Utilities + tools | 음악을 재생하지 않고 곡 정보를 표시하는 도구이므로 선택합니다. |
| 보조 카테고리 | Music | 음악 관련 도구임을 나타냅니다. Store의 Music은 음악을 듣거나 만드는 앱을 위한 분류이므로 주 카테고리로 쓰지 않습니다. |
| 가격 | 무료 | 무료로 제공합니다. |
| 개인정보 접근 여부 | Yes | 곡 정보를 읽습니다. 정책 10.5.1은 Win32/Desktop Bridge 앱에 개인정보 처리방침을 항상 요구합니다. |
| Privacy policy URL | https://github.com/LOONACIA/Soriseom/blob/main/PRIVACY.md | 한국어·영어 개인정보 처리방침으로 연결합니다. |
| Website | https://github.com/LOONACIA/Soriseom | 공개 저장소로 연결합니다. |
| Support contact | https://github.com/LOONACIA/Soriseom/issues | 문의와 문제 보고에 사용합니다. |
| What's new | 비워 둡니다. | 첫 제출이므로 비워 둡니다. |
| Short title | 비워 둡니다. | 별도 짧은 이름을 사용하지 않습니다. |
| Sort title | 비워 둡니다. | 별도 정렬 이름을 사용하지 않습니다. |
| Voice title | 비워 둡니다. | 별도 음성 이름을 사용하지 않습니다. |
| Additional system requirements | 비워 둡니다. | 추가 하드웨어 요구 사항이 없습니다. |

카테고리는 [Store 카테고리 안내](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/categories-and-subcategories)를 참고합니다. 이름에는 설명이나 마케팅 문구를 붙이지 않고, 중요한 제한과 타사 서비스와의 관계를 Description에 명시합니다. 개인정보 접근 여부와 방침은 [Store 정책 10.1.1 및 10.5.1](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies)을 따릅니다.

아래 코드 블록 안의 내용만 해당 필드에 붙여 넣습니다. Product name은 해당 언어로 예약한 이름을 선택하며, 리소스의 `AppDisplayName`과 맞춥니다. Short description은 Description과 함께 표시되므로 첫 문단과 다른 문장으로 작성하고 공백 포함 270자 미만으로 유지합니다. Description은 일반 텍스트 10,000자 이하로 작성하며 HTML, 마크다운 기호, 코드, URL을 넣지 않습니다. Product features는 이 초안에서 3~10개로 구성하고 줄마다 200자 이하로 작성하며, Store가 글머리 기호를 붙이므로 직접 넣지 않습니다. [등록 문구 안내](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/add-and-edit-store-listing-info)를 참고합니다.

Keywords는 줄마다 하나씩 입력합니다. 최대 7개, 각 40자 이하, 전체 21단어 이하로 유지하고 다른 회사의 상표나 일반적인 홍보 단어를 넣지 않습니다. [키워드 안내](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/add-additional-information)를 참고합니다.

## Submission options

`runFullTrust` 사유(Why do you need the runFullTrust capability?):

```text
Soriseom is a WinUI 3 desktop app built with the Windows App SDK. Packaged desktop apps run as full-trust processes, and this app model requires the capability. The app runs in the system tray after its settings window closes, starts at sign-in unless the user turns that off in its settings, and shows a click-through popup that does not take focus. It does not use the network or collect data.
```

Notes for certification:

```text
No account or sign-in is required. The app shows a popup only when the track in the current Windows media session changes, so a track that is already playing when the app starts shows no popup.
To test: 1. Start the app. Its settings window opens on the first launch, and the app stays in the system tray after you close it. 2. Play music in an app that shares track information with Windows media sessions, such as Media Player or a music website in Microsoft Edge. 3. Skip to another track. The popup shows the title, artist, and album art for about 4 seconds at the top center of the primary display. It stays hidden while a fullscreen app is in use or Do Not Disturb is on.
The app starts at sign-in by default, and this can be turned off in its settings. It does not play audio or use the network.
```

## 연령 등급 설문

IARC 설문은 첫 질문에서 고른 앱 분류에 따라 문항이 달라지고 바뀔 수 있으므로, 화면의 문항을 보고 사람이 아래 사실에 맞게 답합니다. 첫 질문에서는 게임이 아닌 앱 분류 중 유틸리티에 가장 가까운 항목을 고릅니다.

| 항목 | 사실 |
|---|---|
| 앱이 직접 제공하는 콘텐츠 | 폭력, 성적 내용, 욕설, 약물, 도박이 없습니다. |
| 표시하는 외부 콘텐츠 | 사용자가 재생 중인 곡의 제목, 아티스트, 앨범아트를 받은 그대로 잠깐 표시합니다. 앱이 곡을 제공하거나 고르지 않습니다. |
| 사용자 간 상호작용 | 없습니다. 채팅, 공유, 사용자 생성 콘텐츠 업로드 기능이 없습니다. |
| 위치와 개인정보 공유 | 없습니다. 네트워크를 쓰지 않고 곡 정보를 PC 밖으로 보내지 않습니다. |
| 구매와 광고 | 없습니다. 무료이고 앱 내 구매와 광고가 없습니다. |
| 웹 접근 | 없습니다. 앱 안에 브라우저나 외부 링크 탐색 기능이 없습니다. |

## 스크린샷

언어마다 PNG 세 장을 올립니다. Claude가 `tools/smoke/Smoke.ps1 -Configuration Release -Scenario storeshots -OutDir <폴더>`로 팝업, 설정 창, 데스크톱 화면을 찍고, `uv run tools/store/compose_screenshots.py <폴더>`로 배경과 문구를 합성한 뒤, 다른 창이나 개인 정보가 없는지 확인합니다(ADR-009). 데스크톱 화면은 Windows 기본 바탕화면(`ThemeC\img28.jpg`)을 창으로 덮어 찍으므로 실제 바탕화면은 바뀌지 않지만, 이 PC의 작업 표시줄(고정한 앱, 트레이, 시계)은 그대로 찍힙니다. 시계는 en-US 이미지에서도 Windows 표시 언어를 따릅니다. 이미지 안의 문구는 합성 스크립트에 있습니다. Microsoft 권장 사항은 스크린샷에 홍보 문구를 넣지 않는 것이지만, 앱이 작은 팝업이라 문구 없이는 기능이 드러나지 않아 넣기로 했습니다(2026-11-06 사용자 결정). 파일과 캡션은 다음과 같습니다.

| 파일 | ko-KR 캡션 | en-US 캡션 |
|---|---|---|
| `store-<언어>-1.png` | 곡이 바뀌면 제목, 아티스트, 앨범아트를 잠깐 표시합니다. | Briefly shows the title, artist, and album art when the track changes. |
| `store-<언어>-2.png` | 작업 중인 화면 위쪽에 잠깐 나타났다가 사라집니다. | Appears briefly at the top of your screen while you work. |
| `store-<언어>-3.png` | 표시 시간, 위치, 크기, 테마와 앱별 표시 여부를 설정합니다. | Choose the display time, position, size, theme, and which apps can show popups. |

## ko-KR

### Product name

```text
소리섬
```

### Short description

```text
음악을 들으며 작업하는 동안 곡 변경을 알약 모양 팝업으로 확인합니다. 표시 시간, 위치, 크기와 앱별 표시 여부를 원하는 대로 설정합니다.
```

### Description

```text
소리섬은 창을 전환하지 않고 지금 나오는 곡을 확인하도록 도와줍니다. 곡이 바뀌면 제목, 아티스트, 앨범아트를 몇 초간 표시한 뒤 사라집니다. 앨범아트가 없으면 음표 아이콘으로 표시합니다.

팝업은 주 모니터에 알약 모양으로 표시합니다. 테마는 기본으로 Windows의 밝게·어둡게 모드를 따르며, 설정에서 직접 고를 수 있습니다. 클릭을 뒤의 창으로 전달하고 입력 중인 창의 포커스를 유지합니다. 작업 표시줄과 Alt+Tab 목록에는 나타나지 않습니다.

표시 시간은 2~10초, 위치는 위·아래의 왼쪽·가운데·오른쪽 6곳, 크기는 70~100%로 설정합니다. 기본값은 4초, 위쪽 가운데, 90%입니다. 앱별로 팝업을 켜거나 끄고, 바꾼 설정은 바로 저장하고 적용합니다. 언어 변경에는 재시작이 필요합니다.

전체화면일 때 숨기기는 기본으로 켜져 있으며 설정에서 끌 수 있습니다. Windows 방해 금지 중에는 표시하지 않습니다. 다만 전체화면 앱을 쓰는 중에는 전체화면 설정만 따릅니다. 방해 금지 상태를 읽을 수 없는 Windows 버전에서는 해당 상태와 관계없이 표시합니다.

같은 곡을 반복해 제목과 아티스트가 그대로면 다시 표시하지 않습니다. 일시정지 중에 곡 정보가 바뀌면 그 곡의 재생을 시작할 때 표시합니다.

Windows 미디어 세션에 곡 정보를 보내는 앱만 지원합니다. 호환 예로 Spotify와 브라우저에서 재생하는 YouTube Music이 있으며, 곡 정보를 Windows에 제공하는 경우에 동작합니다. 소리섬은 Spotify 및 YouTube Music의 운영 회사와 제휴 관계가 없습니다. 브라우저는 앱 단위로만 구분하며 사이트별로 구분하지 않습니다.

소리섬은 음악을 재생하지 않으며 재생 조작, 진행 바, 앨범명 표시를 제공하지 않습니다. 전용 전체화면(exclusive fullscreen) 게임 위에는 팝업을 표시하지 못합니다.

설정 창을 닫아도 시스템 트레이에 상주합니다. 트레이에서 설정을 열거나 앱을 종료합니다. Windows 로그인 시 자동 실행은 기본으로 켜져 있으며 설정에서 끌 수 있습니다.

Windows 10 1809 이상과 Windows 11을 대상으로 하며 한국어와 영어 UI를 제공합니다. MIT 라이선스의 무료 오픈 소스 앱으로, 로그인 없이 사용합니다. 네트워크를 사용하거나 데이터를 수집하지 않으며, 곡 정보는 PC 밖으로 보내지 않습니다. 설정과 감지된 앱 목록은 기기에 저장합니다.
```

### Product features

```text
곡이 바뀌면 제목, 아티스트, 앨범아트를 잠깐 표시합니다.
클릭을 뒤의 창으로 전달하고 작업 중인 창의 포커스를 유지합니다.
표시 시간 2~10초, 위치 6곳, 크기 70~100%를 설정합니다.
알약 모양으로 표시하며 밝게·어둡게 테마를 고르거나 Windows 모드를 따릅니다.
앱별로 팝업을 켜거나 끄고 전체화면일 때 숨기기를 설정합니다.
트레이에 상주하며 로그인 시 자동 실행을 켜거나 끄도록 지원합니다.
한국어와 영어 UI를 제공합니다.
로그인과 네트워크 사용 없이 곡 정보를 기기 안에서만 처리합니다.
```

### Keywords

```text
곡 알림
음악 팝업
현재 재생 정보
앨범아트
곡 제목
미디어 세션
트레이 도구
```

## en-US

### Product name

```text
Soriseom
```

### Short description

```text
Keep track of your music while you work with a pill-shaped popup for each new track. Choose its duration, position, and size, and decide which apps can show popups.
```

### Description

```text
See what's playing without switching windows. Soriseom briefly shows the title, artist, and album art when the track changes, then disappears. If no album art is available, it shows a music note icon.

The pill-shaped popup appears on your primary monitor. It follows your Windows light or dark mode by default, or you can choose a theme in settings. Clicks pass through to the window behind it, and your current window keeps focus. The popup stays out of the taskbar and Alt+Tab.

Choose a display time of 2 to 10 seconds, one of six positions across the top or bottom of the screen, and a size from 70% to 100%. The defaults are 4 seconds, top center, and 90%. Turn popups on or off for each app. Settings are saved and applied as you change them; changing the UI language requires a restart.

Popups are hidden during fullscreen use by default, with an option to turn this off. They are also hidden while Windows Do Not Disturb is on. During fullscreen use, only the fullscreen setting applies. On Windows versions that do not provide access to the Do Not Disturb status, Soriseom shows popups regardless of that status.

Repeating a track with the same title and artist does not trigger another popup. If track information changes while playback is paused, the popup waits until that track starts playing.

Soriseom only supports apps that share track information through Windows media sessions. Compatibility examples include Spotify and YouTube Music playing in a browser, when they provide that information to Windows. Soriseom is not affiliated with the companies behind Spotify or YouTube Music. Browsers are identified as apps; individual websites cannot be managed separately.

Soriseom does not play music or offer playback controls, a progress bar, or album names. It cannot display popups over games running in exclusive fullscreen mode.

Soriseom stays in the system tray when you close its settings window. Use the tray to open settings or quit. Starting automatically when you sign in to Windows is enabled by default and can be turned off in settings.

Designed for Windows 10 version 1809 or later and Windows 11, with a Korean and English interface. Soriseom is free and open source under the MIT license. No account is needed. It makes no network requests, collects no data, and never sends track information off your PC. Settings and the list of detected apps are saved on your device.
```

### Product features

```text
Briefly displays the title, artist, and album art when the track changes
Lets clicks pass through and keeps focus on your current window
Offers a 2 to 10 second display time, six positions, and 70% to 100% sizing
Shows a pill-shaped popup in light or dark, following Windows or your choice
Lets you enable popups per app and choose whether to hide them during fullscreen use
Runs in the system tray with optional startup when you sign in
Includes Korean and English interfaces
Processes track information on your device with no account or network access
```

### Keywords

```text
track notification
music popup
now playing
album art
song title
media session
tray utility
```
