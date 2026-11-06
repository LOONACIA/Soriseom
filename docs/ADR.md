# Architecture Decision Records

> 되돌리기 어려운 기술 결정만 기록합니다. 스텝 description에서 "이 결정을 벗어나지 마라"의 근거로 씁니다. 결정은 2026-10-29 설계 인터뷰에서 사용자가 정했습니다.

## 원칙

- 동작하는 최소한의 구현을 우선합니다. `docs/PRD.md`에 없는 기능, 설정, 확장 지점을 넣지 않습니다.
- 외부 NuGet 의존성은 아래 목록만 씁니다. 다른 패키지가 필요하면 먼저 ADR을 추가합니다.
  - `Microsoft.WindowsAppSDK` (ADR-002)
  - `CommunityToolkit.Mvvm` (ADR-002)
  - `H.NotifyIcon.WinUI` (ADR-002)
  - `Microsoft.Windows.CsWin32` (ADR-008)
  - `StyleCop.Analyzers` 1.3 이상 (ADR-006)
  - 테스트용: `xunit.v3`, `xunit.runner.visualstudio`, `Microsoft.NET.Test.Sdk` (ADR-004)
  - 위 패키지를 만들 때 템플릿이 자동으로 함께 추가하는 패키지

---

### ADR-001: Windows 전용, 곡 정보는 GSMTC로 가져온다

- **상태**: 채택
- **결정**: Windows 10 1809 이상과 Windows 11만 지원합니다. 곡 정보는 `Windows.Media.Control`의 GSMTC(Global System Media Transport Controls)에서 가져옵니다.
- **이유**: 플레이어와 상관없이 로그인 없이 지원할 수 있습니다. 사용자는 주로 브라우저로 듣고, Chrome·Edge·Firefox는 재생 정보를 미디어 세션으로 넘깁니다.
- **트레이드오프**: 미디어 세션에 정보를 보내지 않는 플레이어는 지원하지 못합니다. 브라우저 안의 사이트(YouTube와 YouTube Music)를 구분할 수 없습니다. macOS와 Linux는 지원하지 않습니다.
- **하네스에 미치는 영향**: 서비스별 API(Spotify Web API 등), 네트워크 호출, 창 제목이나 프로세스 메모리를 읽는 방식을 추가하지 마세요.

### ADR-002: C#과 WinUI 3, MVVM은 CommunityToolkit.Mvvm, 트레이는 H.NotifyIcon.WinUI

- **상태**: 채택
- **결정**: .NET 10과 Windows App SDK(WinUI 3)로 만듭니다. 설정 창은 CommunityToolkit.Mvvm으로 MVVM을 구성합니다. WinUI 3에는 트레이 API가 없어서 H.NotifyIcon.WinUI를 씁니다.
- **이유**: GSMTC를 직접 호출할 수 있고, Windows 11 스타일(Acrylic)의 UI를 만들 수 있습니다. CommunityToolkit.Mvvm은 Microsoft가 관리하며 `INotifyPropertyChanged` 보일러플레이트를 소스 생성기로 없애줍니다.
- **검토한 대안**: WPF(투명 창은 쉽지만 UI가 구식), Tauri(Rust 필요), Electron(메모리와 용량이 큼)
- **트레이드오프**: 투명 창과 클릭 통과 처리가 WPF보다 까다롭습니다. 트레이 기능을 외부 라이브러리에 의존합니다.
- **하네스에 미치는 영향**: WPF나 WinForms 타입을 섞지 마세요(트레이에 WinForms `NotifyIcon` 사용 금지). `INotifyPropertyChanged`를 직접 구현하지 말고 `[ObservableProperty]`와 `[RelayCommand]`를 쓰세요.

### ADR-003: Microsoft Store 전용 배포, MSIX 패키지 앱

- **상태**: 채택
- **결정**: MSIX 패키지 앱으로 만들고 Microsoft Store로만 배포합니다. unpackaged 실행은 지원하지 않습니다.
- **이유**: Store가 코드 서명, 업데이트, Windows App SDK 런타임 설치를 대신 처리합니다.
- **트레이드오프**: GitHub Releases, winget, 설치 프로그램으로는 배포하지 않습니다. 패키지 ID가 Partner Center에 묶입니다. 저장소의 매니페스트는 임시 패키지 ID를 유지하고, Store 패키지를 만들 때만 Partner Center의 값을 넣습니다(ADR-007).
- **하네스에 미치는 영향**: 패키지 ID가 필요한 API(`ApplicationData`, `StartupTask`)는 써도 됩니다. 설치 프로그램(Inno Setup 등), 자체 업데이트 코드, unpackaged용 분기 코드를 추가하지 마세요.

### ADR-004: Core와 App 분리, Core는 순수 .NET이고 Core만 테스트한다

- **상태**: 채택
- **결정**: 판단 로직은 `Soriseom.Core`(net10.0)에 두고, Windows에 의존하는 코드는 `Soriseom.App`에 둡니다. 자동 테스트는 xUnit v3로 Core만 작성합니다.
- **이유**: 곡 변경 판단과 표시 여부 같은 핵심 규칙을 결정적으로 테스트할 수 있습니다. WinUI 3 UI 자동화는 비용이 큽니다.
- **트레이드오프**: 어댑터 계층 코드가 늘어납니다. UI, GSMTC 연동, 셸 연동은 빌드 성공과 수동 확인으로만 검증합니다(2026-11-03에 ADR-009가 스모크 스크립트를 더했습니다).
- **하네스에 미치는 영향**: Core에 `Windows.*`나 `Microsoft.UI.*` 참조를 추가하지 마세요. Core에서 타이머나 `DateTime.Now`를 쓰지 마세요. 새 판단 로직은 Core에 두고 같은 스텝에서 테스트를 함께 작성하세요.

### ADR-005: 데이터 수집과 네트워크 없음

- **상태**: 채택
- **결정**: 텔레메트리, 크래시 리포트, 로그 파일, 네트워크 호출을 넣지 않습니다. 진단은 디버그 출력으로만 합니다.
- **이유**: 듣는 음악 정보가 PC 밖으로 나가지 않습니다. 구현이 단순해지고 Store 개인정보 처리방침도 간단해집니다.
- **트레이드오프**: 사용자 환경에서 생긴 문제를 진단하기 어렵습니다.
- **하네스에 미치는 영향**: `HttpClient`, Application Insights, Sentry 같은 전송 수단이나 파일 로거를 추가하지 마세요.

### ADR-006: 품질 게이트는 경고=오류, .editorconfig, StyleCop.Analyzers

- **상태**: 채택
- **결정**: 모든 프로젝트에 다음을 적용합니다.
  - `TreatWarningsAsErrors`. NuGet 취약점 감사 경고 NU1901~NU1904와 트리밍 경고 IL2104(ADR-010)는 경고로 남깁니다.
  - `Nullable`, `EnforceCodeStyleInBuild`, `GenerateDocumentationFile`(CS1591 끔)
  - StyleCop.Analyzers 1.3 이상. 1.2.x 이하는 C# 14 문법에서 오탐이 나므로 쓰지 않습니다.
  - 모든 하네스 스텝의 AC에 `dotnet format --verify-no-changes` 포함
- **StyleCop 규칙 조정**:
  - SA1101(`this.` 강제), SA1309(필드 밑줄 금지): 끕니다. private 필드는 `_camelCase`로 쓰고 `this.`는 붙이지 않습니다.
  - SA1633(파일 헤더): 끕니다. 파일 헤더를 넣지 않습니다.
  - SA1600, SA1601, SA1602(문서 주석 필수): 끕니다. 문서 주석은 쓴 곳의 형식만 검사합니다.
  - `using`은 namespace 밖에 둡니다(`stylecop.json`의 `usingDirectivesPlacement: outsideNamespace`).
- **이유**: Codex가 만든 코드의 일관성을 사람의 리뷰가 아니라 기계적으로 강제합니다. 2026-10-29에 .NET 10 임시 프로젝트로 확인해 보니, 1.2.0-beta.556은 C# 14 문법에서 오탐을 냈고(`field` 키워드에 초기화 값을 붙인 속성에 SA1500·SA1513, `extension` 블록 수신자에 SA1101), 1.3.151-beta는 같은 코드를 정상으로 처리했습니다.
- **트레이드오프**: 프리릴리스에 의존합니다. 1.3.x는 2026-10-13에 처음 나왔고 자주 바뀌고 있습니다. 규칙 조정이 필요합니다.
- **하네스에 미치는 영향**: `#pragma warning disable`나 `[SuppressMessage]`로 경고를 숨기지 마세요. 규칙 조정은 `.editorconfig`에서 사유 주석과 함께, 계획에 명시된 경우에만 합니다.

### ADR-007: 릴리스 자동화는 태그 push → Store 제출 → 인증 통과 시 자동 게시

- **상태**: 채택(제출 도구는 2026-11-05 확정)
- **결정**: GitHub Actions에서 `vX.Y.Z` 태그를 push하면 빌드, 테스트, 패키지 버전 `X.Y.Z.0`의 `.msixupload` 생성, Store 제출을 차례로 진행하고, 인증을 통과하면 자동으로 게시합니다. 제출 도구는 Microsoft Store Developer CLI(`msstore publish`)입니다. 같은 워크플로를 수동 실행하면 제출하지 않고 패키지만 아티팩트로 만듭니다. 패키지는 x64만 올리고 기호 패키지는 넣지 않습니다.
- **이유**: 태그를 올리는 것 자체가 출시 결정이므로 수작업을 줄입니다. 스모크로 확인한 아키텍처는 x64뿐입니다. `dotnet build`에는 `mspdbcmf.exe`가 없어 기호 패키지를 만들지 못합니다(2026-11-05 확인).
- **트레이드오프**: 잘못 올린 태그도 인증만 통과하면 게시됩니다. Entra ID 자격 증명을 관리해야 합니다. Microsoft 문서 기준으로 자동 제출은 이미 게시된 앱에만 쓸 수 있어 최초 제출은 Partner Center에서 직접 합니다. 32비트 Windows에는 설치되지 않고, ARM64 PC에서는 Windows 11의 x64 에뮬레이션에 의존합니다. 기호가 없어 Partner Center의 크래시 분석 정보가 제한됩니다.
- **하네스에 미치는 영향**: 자격 증명과 패키지 식별 정보를 워크플로나 저장소에 하드코딩하지 마세요. GitHub Secrets만 씁니다. `Package.appxmanifest`의 `Soriseom.Dev`는 개발 패키지용이니 바꾸지 마세요. 실제 값은 `tools/store/Build-StorePackage.ps1`이 빌드하는 동안에만 넣습니다.

### ADR-008: Win32 P/Invoke는 CsWin32로 생성한다

- **상태**: 채택
- **결정**: App에서 Win32 API(창 확장 스타일, DWM, DPI, 셸 알림 상태)를 부를 때는 `Microsoft.Windows.CsWin32` 소스 생성기를 씁니다. 필요한 API 이름을 `src/Soriseom.App/NativeMethods.txt`에 적고, 생성된 `Windows.Win32.PInvoke`와 타입(`HWND`, `HRESULT`, enum)을 씁니다.
- **이유**: App 코드는 빌드와 수동 확인으로만 검증하므로(ADR-004) 손으로 쓴 시그니처가 틀리면 실행해야 드러납니다. CsWin32는 공식 Win32 메타데이터에서 CPU 아키텍처별로 맞는 선언과 상수를 만듭니다. 개발 의존성이라 앱에 런타임 의존성을 더하지 않습니다.
- **검토한 대안**: `[LibraryImport]` 직접 선언(의존성은 없지만 시그니처와 상수를 손으로 관리하고, Win32 상수 이름을 StyleCop 규칙에 맞게 바꿔야 함)
- **트레이드오프**: 0.x 버전이고, 빌드할 때 함께 받는 메타데이터 패키지(`Microsoft.Windows.SDK.Win32Metadata` 등)는 preview/experimental입니다. 생성 코드가 저장소에 없어 리뷰할 때 시그니처를 diff로 볼 수 없습니다. 2026-10-29에 0.3.330이 이 저장소 설정(경고=오류, StyleCop, x64·x86·ARM64)에서 경고 없이 빌드되는 것을 확인했습니다.
- **하네스에 미치는 영향**: `[DllImport]`나 `[LibraryImport]`로 Win32 함수를 직접 선언하지 마세요. 필요한 API는 `NativeMethods.txt`에 이름을 추가하세요. Win32 상수를 직접 정의하지 말고 생성된 enum과 상수를 쓰세요.

### ADR-009: App은 스모크 스크립트로 실행해 검증하고, Codex는 앱을 실행하지 않는다

- **상태**: 채택(2026-11-03, 사용자 결정). ADR-004의 "수동 확인으로만 검증"을 일부 대체합니다.
- **결정**: `tools/smoke/Smoke.ps1`이 현재 빌드를 개발 패키지로 등록하고 UI Automation으로 앱을 조작해 확인합니다. Claude만 실행합니다. 하네스에서는 App을 바꾼 계획을 마무리할 때 `-Configuration Release`로 한 번 돌리고, 스텝마다 돌리지 않습니다.
- **이유**: 사람이 Visual Studio에서 확인할 때까지 App 변경의 동작을 알 수 없었습니다. 2026-11-03 시험에서 설정 창, 단일 인스턴스, 자동 실행 스위치, 언어, 팝업, 앱 이름, 트레이 왼쪽 클릭을 자동으로 확인했습니다. PowerShell에 있는 UI Automation 어셈블리만 쓰므로 NuGet 패키지가 늘지 않습니다.
- **트레이드오프**: 실제 데스크톱에서 돌아 창이 뜨고 포커스를 가져갈 수 있습니다(개발 PC가 Windows 11 Home이라 Windows Sandbox가 없음). 화면이 잠겼거나, 전체화면이거나, 다른 미디어가 현재 세션을 가져가면 판정할 수 없어 종료 코드 3을 돌려줍니다. 문제는 커밋 뒤에 드러나므로 새 스텝으로 고칩니다. CI에서는 돌리지 않습니다.
- **스크립트가 못 보는 항목(사람이 확인)**:
  - 트레이 오른쪽 클릭 메뉴와 메뉴로 종료: 합성 입력으로 연 메뉴를 UI Automation에서 찾지 못했습니다.
  - 실제 로그인 시 자동 실행: 로그아웃하면 세션이 끝납니다. 재로그인은 사람이 하고, 그 뒤 `-AfterSignIn`으로 판정합니다.
  - 작업 관리자에서 끈 상태: 레지스트리의 `State` 값을 직접 바꿔 흉내 냅니다. 작업 관리자 조작 자체는 아닙니다.
  - 두 번째 실행 때 창이 앞으로 오는지: 스크립트는 백그라운드에서 실행해 포그라운드 잠금에 걸립니다.
  - 모양과 느낌: 스크린샷으로 배치와 글자는 보지만, 애니메이션과 Acrylic의 느낌은 판단하지 못합니다. Acrylic으로 뒤가 비치는지와 가장자리가 계단처럼 끊기지 않는지는 media 시나리오가 확인합니다. Windows 설정에서 투명 효과를 껐을 때 글자가 읽히는지는 사람이 확인합니다.
  - 작업 표시줄 테마 전환: Windows 모드를 바꾸면 화면 전체가 바뀌므로 스크립트가 건드리지 않습니다. 설정에서 Windows 모드를 바꿨을 때 트레이 아이콘이 따라 바뀌는지 사람이 확인합니다. 이때 앱이 종료되지 않는지, 앱 테마가 "시스템 설정 사용"일 때 팝업과 설정 창 색이 바뀐 Windows 모드를 따르는지도 확인합니다. 밝게·어둡게를 고른 경우는 theme 시나리오가 Windows 모드의 반대쪽을 골라 설정 창의 배경과 제목 표시줄, 팝업의 밝기로 확인합니다.
  - 전체화면 중의 방해 금지: 화면 전체를 가리는 창을 띄워야 해서 스크립트가 만들지 않습니다. Core 테스트가 규칙을 검증하니, 사람은 "전체화면일 때 숨기기"를 끄고 전체화면에서 곡을 넘겨 팝업이 뜨는지 확인합니다. dnd 시나리오는 Windows 설정의 방해 금지 스위치를 UI Automation으로 켰다가 끕니다. AutomationId는 공개 계약이 아니므로 Windows 업데이트로 깨질 수 있습니다.
- **하네스에 미치는 영향**: 앱을 실행하는 명령을 `ac`에 넣지 마세요. Codex에게 앱을 실행하게 하지 마세요. `tools/smoke/`는 App 코드가 아니므로 `[DllImport]`를 쓸 수 있습니다(ADR-008 대상 아님). 곡 제목처럼 사용자의 데이터를 출력이나 로그에 남기지 마세요. 테스트 곡만 판정하고 다른 제목은 읽어 내지 않습니다. 스크립트는 앱의 `PopupTrace` 출력을 `<OutDir>/app-trace.log`에 저장합니다. Release 빌드에는 이 출력이 없으니, 판단 경로를 봐야 하는 실패는 Debug로 다시 돌립니다. `storeshots` 시나리오는 팝업과 설정 창 영역, 그리고 작업 표시줄을 포함한 화면 전체를 그대로 복사하므로, 결과를 쓰기 전에 다른 창이나 개인 정보가 찍히지 않았는지 이미지를 직접 확인하세요.

### ADR-010: Release는 트리밍을 유지하고 IL2104만 오류에서 뺀다

- **상태**: 채택(2026-11-04, 사용자 결정)
- **결정**: App 템플릿대로 Release에서 `PublishTrimmed`를 켜 둡니다. `Directory.Build.props`의 `WarningsNotAsErrors`에 IL2104를 더하고, 다른 트리밍 경고는 오류로 둡니다.
- **이유**: 2026-11-04에 x64 패키지를 만들어 비교했습니다. 트리밍을 켜면 번들 32MB, 설치 크기 75MB이고, 끄면 81MB, 217MB입니다. 트리밍한 Release 빌드는 `tools/smoke/Smoke.ps1`의 31개 항목을 모두 통과했습니다. 문제가 생기면 `PublishTrimmed` 한 줄로 끌 수 있습니다.
- **트레이드오프**: `Microsoft.Windows.SDK.NET`과 `WinRT.Runtime`은 트리밍에 안전하다는 보장이 없어서, 제거된 코드가 필요한 경로는 실행 중에 깨질 수 있습니다. IL2104는 어셈블리 단위 경고라 다른 어셈블리에서 나와도 빌드를 막지 못합니다. 2026-11-04 기준으로 이 경고를 내는 어셈블리는 위 두 개뿐이고, 늘어났는지는 Release 빌드 출력에서 봅니다.
- **스모크가 못 보는 경로(출시 전 사람이 확인)**: 실제 앨범아트 로드(테스트 곡에는 썸네일이 없음), 트레이 오른쪽 클릭 메뉴와 종료, Windows 모드 전환.
- **하네스에 미치는 영향**: IL2104 말고 다른 트리밍 경고를 `WarningsNotAsErrors`에 더하지 마세요. Release 전용 코드 분기를 넣지 마세요.
