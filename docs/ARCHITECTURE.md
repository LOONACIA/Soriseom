# 아키텍처

> 아직 코드가 없어서 합의한 목표 구조를 적었습니다. 이름(클래스, 파일)은 예시이며 구현 스텝에서 확정합니다. 실제 코드와 어긋나면 코드가 아니라 이 문서를 고치세요.

## 디렉토리 구조

```
Soriseom.slnx
global.json                 # dotnet test를 Microsoft Testing Platform으로 실행(xUnit v3에 필요)
Directory.Build.props       # 공통 빌드 설정: Nullable, 경고=오류, 분석기
Directory.Packages.props    # NuGet 버전 중앙 관리(Central Package Management)
.editorconfig               # 코드 스타일, 분석기 규칙 조정
stylecop.json               # StyleCop 설정(using 위치 등)
src/
├── Soriseom.Core/          # net10.0. 곡 변경 판단, 표시 여부 결정, 설정 모델. Windows API 참조 금지
└── Soriseom.App/           # net10.0-windows10.0.26100.0, 최소 10.0.17763.0. WinUI 3 + MSIX
                            # GSMTC 어댑터, 팝업 창, 설정 창, 트레이, 시작 작업, 리소스(.resw)
tests/
└── Soriseom.Core.Tests/    # xUnit v3. Core만 테스트
tools/
├── icons/                  # 앱·트레이 아이콘 SVG 원본과 에셋 생성 스크립트(uv로 실행, 앱에 포함되지 않음)
└── smoke/                  # 앱을 실행해 UI Automation으로 확인하는 스크립트(ADR-009)
.github/workflows/          # CI: 빌드·테스트·포맷, 태그 시 Store 제출
docs/                       # PRD, ARCHITECTURE, ADR
```

## 레이어 규칙

- 의존 방향은 App → Core 하나뿐입니다. Core는 App, `Windows.*`(WinRT), `Microsoft.UI.*`(WinUI)를 참조하지 않습니다. 이유: Core를 Windows 런타임 없이 결정적으로 테스트하기 위해서입니다.
- Core는 타이머, 스레드, 현재 시각을 직접 쓰지 않습니다. 현재 시각은 인자로 받고, 나중에 다시 평가해야 하면 그 시각을 결과로 돌려줍니다. 타이머는 App이 돌립니다. 이유: 테스트가 실제 시간에 의존하지 않게 하고, 시간 추상화 패키지를 추가하지 않기 위해서입니다.
- GSMTC(`Windows.Media.Control`)는 App의 어댑터 한 곳에서만 다룹니다. 어댑터는 WinRT 객체를 Core의 불변 레코드(미디어 스냅샷)로 바꿔 넘깁니다.
- ViewModel은 App에 두고 바인딩과 명령만 담습니다. 기본값, 허용 범위(표시 시간 2~10초 등), 새 앱 기본값 같은 규칙은 Core의 설정 모델에 둡니다.
- 설정을 저장하는 코드는 App에 있고(`ApplicationData.Current.LocalSettings`), Core는 설정 값 객체만 다룹니다.

## 데이터 흐름

```
GSMTC SessionManager
  이벤트: 현재 세션 변경, 미디어 속성 변경, 재생 상태 변경
    │
    ▼
App: 미디어 세션 어댑터
  WinRT 객체 → MediaSnapshot(앱 ID, 제목, 아티스트, 재생 중 여부) + 썸네일 스트림 참조
    │
    ▼
Core: 팝업 결정기
  입력: 스냅샷, 설정, 환경(전체화면 여부, 방해 금지 여부), 현재 시각
  출력: 표시 / 교체 / 없음, 다시 평가할 시각(브라우저 갱신 대기용)
    │
    ▼
App: 팝업 창
  썸네일 로드 → 정사각형 crop(실패 시 음표 아이콘) → 표시 또는 교체 → 표시 시간 뒤 숨김
```

## 창과 셸 연동 (App)

- **팝업 창**: 테두리 없음, 항상 위, 활성화하지 않음(포커스 유지), 작업 표시줄과 Alt+Tab에서 제외, 클릭 통과, Acrylic 배경. 위치는 주 모니터 작업 영역 기준 6곳이고 DPI 배율을 반영합니다. 창 바탕은 `TransparentBackdrop`으로 투명하게 두고 보이는 모양은 XAML로 그립니다. `SetLayeredWindowAttributes`를 부르거나 DWM 둥근 모서리를 켜면 바탕이 불투명해집니다. Acrylic은 `SystemBackdropElement`에 `PopupAcrylicBackdrop`을 붙여 알약 안에만 입힙니다. 창이 활성화되지 않아 기본 `DesktopAcrylicBackdrop`은 단색으로 보이므로 `IsInputActive`를 켠 채 둡니다. 기본 농도는 어두운 화면에서 거의 비치지 않아 `LuminosityOpacity`를 라이트 0.70, 다크 0.80으로 낮췄고, 값을 직접 넣으므로 테마가 바뀔 때마다 다시 넣습니다. 더 낮추면 보조 글자 대비가 4.5:1 아래로 내려갑니다. `SystemBackdropElement`의 `CornerRadius`는 가장자리가 계단처럼 끊기고 Composition의 둥근 clip은 Acrylic과 그 조상에서 무시되므로, Acrylic 브러시에 알약 모양 알파 마스크(`PillAlphaMask`)를 씌웁니다. 컨트롤러가 브러시를 넣을 때마다 마스크를 입히도록 컨트롤러와 실제 대상 사이에 `MaskedBackdropTarget`을 둡니다. 비주얼 서피스에 그린 도형도 가장자리가 끊기므로 마스크의 경계는 그라디언트로 만듭니다. 계단을 불투명 테두리로 가리면 Acrylic이 없는 띠가 보여서 쓰지 않습니다. 작은 원은 `IslandSurface`의 폭으로 만들고 마스크와 내용의 clip이 그 폭을 따라갑니다. 폭은 레이아웃 속성이라 이 애니메이션만 UI 스레드에서 돕니다. Acrylic을 지원하지 않는 환경과 마스크 API가 없는 Windows 10 1809(10.0.18362 미만)에서는 단색 배경을 씁니다. 크기 설정은 창 크기만 바꾸고, `Viewbox`가 360×80 DIP로 배치한 내용을 창에 맞춰 줄입니다. 그래서 애니메이션 값은 크기 설정과 상관없이 배치 단위 그대로 씁니다. 글자는 화면에서 12 DIP 밑으로 내려가지 않도록 배치 단위의 글자 크기를 키웁니다.
- **트레이**: H.NotifyIcon.WinUI. 왼쪽 클릭은 설정 창, 오른쪽 클릭은 메뉴(설정, 종료)입니다. 아이콘은 작업 표시줄 테마(`SystemUsesLightTheme`)를 따르며 앱 테마와 다를 수 있습니다. 실행 중 변경은 `UISettings.ColorValuesChanged`로 감지합니다.
- **단일 인스턴스**: Windows App SDK의 `AppInstance`로 두 번째 실행을 기존 인스턴스로 넘기고, 기존 인스턴스는 설정 창을 엽니다.
- **자동 실행**: MSIX `StartupTask`를 매니페스트에서 `Enabled="true"`로 선언해 기본으로 켜고, 설정에서 끄고 켭니다. 상태의 원본은 `StartupTask.State`이며 LocalSettings에 저장하지 않습니다. 시작 방식은 `AppInstance.GetActivatedEventArgs().Kind`로 구분해 자동 실행이면 창을 열지 않습니다.
- **전체화면 감지**: `SHQueryUserNotificationState`를 써서 Windows 알림과 같은 기준으로 판단합니다.
- **방해 금지 감지**: `ToastNotificationManagerForUser.NotificationMode`가 `Unrestricted`가 아니면 켜진 것으로 봅니다. 곡을 판단할 때마다 읽으므로 `NotificationModeChanged`를 구독하지 않습니다. 문서 기준 10.0.23504 미만의 Windows에는 이 속성이 없어 `ApiInformation`으로 확인하고, 없으면 꺼진 것으로 봅니다. `SHQueryUserNotificationState`는 방해 금지를 반영하지 않습니다. 전체 화면 창을 띄우면 Windows 자동 규칙으로 값이 `AlarmsOnly`가 되므로, 전체화면 중에는 Core가 이 값을 보지 않습니다.

## 횡단 관심사

- **에러 처리**: GSMTC, 썸네일, 셸 API가 실패해도 앱이 종료되지 않습니다. 썸네일을 못 읽으면 음표 아이콘을 쓰고, 세션 정보를 못 읽으면 그 팝업만 건너뜁니다. 예외는 디버그 출력에 남깁니다.
- **로깅**: `System.Diagnostics.Debug` 출력만 씁니다. 파일 로그와 네트워크 전송은 없습니다.
- **설정 저장**: `ApplicationData.Current.LocalSettings`. 키 이름은 한 곳에 상수로 모읍니다.
- **현지화**: `Strings/en-US/Resources.resw`, `Strings/ko-KR/Resources.resw`. 언어를 직접 고르면 `ApplicationLanguages.PrimaryLanguageOverride`로 바꿉니다. 언어 리소스는 번들의 기본 패키지에 넣습니다(`AppxBundleAutoResourcePackageQualifiers`). 그렇지 않으면 Store 번들에 한국어가 들어가지 않습니다.
- **의존성**: Central Package Management로 버전을 고정합니다. 허용 목록은 `docs/ADR.md`의 "원칙"에 있습니다.
- **품질 게이트**: `Directory.Build.props`에서 Nullable, `TreatWarningsAsErrors`(NU1901~NU1904, IL2104 제외), `EnforceCodeStyleInBuild`, `GenerateDocumentationFile`(CS1591 끔)을 켭니다. StyleCop 규칙 조정은 `docs/ADR.md` ADR-006을 따릅니다.
- **CI**: GitHub Actions(Windows runner). `.github/workflows/ci.yml`이 브랜치 push와 PR에서 빌드, 테스트, 포맷 검사, x64 Release MSIX 생성을 돌립니다. `vX.Y.Z` 태그를 push하면 패키지 버전 `X.Y.Z.0`으로 MSIX를 만들어 Store에 제출하고, 인증을 통과하면 자동으로 게시합니다(아직 없음, ADR-007).

## 구현 전에 확인할 것

관련 스텝을 계획하기 전에 확인하고, 결과를 이 문서나 ADR에 반영합니다.

- [x] Release 빌드와 패키징: 트리밍을 유지하고 IL2104만 오류에서 뺍니다(ADR-010).
- [ ] 패키지 앱에서 GSMTC를 쓰는 데 별도 capability가 필요한지
- [x] WinUI 3 창에 Acrylic 배경과 클릭 통과(확장 창 스타일)를 함께 적용할 수 있는지: 됩니다. 2026-11-04에 Windows 11의 임시 창에서 화면 픽셀과 WindowFromPoint로 확인했습니다.
- [x] Windows 방해 금지 모드를 감지할 공식 API가 있는지: 있습니다. 2026-11-04에 Windows 11(빌드 26300)에서 설정의 스위치를 켜면 `PriorityOnly`, 끄면 `Unrestricted`가 되는 것을 확인했습니다. 더 낮은 버전은 확인하지 않았습니다.
- [x] 언어 변경이 재시작 없이 반영되는지: `PrimaryLanguageOverride`는 이미 불러온 UI에 바로 반영된다는 보장이 없고 `x:Uid` 문자열도 갱신되지 않으므로, 재시작을 안내합니다.
- [ ] Store 자동 제출 방식(msstore CLI와 Entra ID 앱 연동), 최초 제출을 수동으로 해야 하는지
- [ ] Windows 10에서 팝업 바깥이 투명하게 보이는지: 2026-11-04에 Windows 11에서만 확인했습니다. SetLayeredWindowAttributes 없는 레이어드 창은 Windows 10에서 보이지 않을 수 있습니다. Acrylic도 Windows 11에서만 확인했습니다.

