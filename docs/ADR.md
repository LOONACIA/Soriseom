# Architecture Decision Records

> 되돌리기 어려운 기술 결정만 기록합니다. 스텝 description에서 "이 결정을 벗어나지 마라"의 근거로 씁니다. 결정은 2026-10-29 설계 인터뷰에서 사용자가 정했습니다.

## 원칙

- 동작하는 최소한의 구현을 우선합니다. `docs/PRD.md`에 없는 기능, 설정, 확장 지점을 넣지 않습니다.
- 외부 NuGet 의존성은 아래 목록만 씁니다. 다른 패키지가 필요하면 먼저 ADR을 추가합니다.
  - `Microsoft.WindowsAppSDK` (ADR-002)
  - `CommunityToolkit.Mvvm` (ADR-002)
  - `H.NotifyIcon.WinUI` (ADR-002)
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
- **트레이드오프**: GitHub Releases, winget, 설치 프로그램으로는 배포하지 않습니다. 패키지 ID가 Partner Center에 묶입니다. 개발 중에는 임시 패키지 ID를 쓰다가 이름을 예약한 뒤 Partner Center의 값으로 바꿉니다.
- **하네스에 미치는 영향**: 패키지 ID가 필요한 API(`ApplicationData`, `StartupTask`)는 써도 됩니다. 설치 프로그램(Inno Setup 등), 자체 업데이트 코드, unpackaged용 분기 코드를 추가하지 마세요.

### ADR-004: Core와 App 분리, Core는 순수 .NET이고 Core만 테스트한다

- **상태**: 채택
- **결정**: 판단 로직은 `Soriseom.Core`(net10.0)에 두고, Windows에 의존하는 코드는 `Soriseom.App`에 둡니다. 자동 테스트는 xUnit v3로 Core만 작성합니다.
- **이유**: 곡 변경 판단과 표시 여부 같은 핵심 규칙을 결정적으로 테스트할 수 있습니다. WinUI 3 UI 자동화는 비용이 큽니다.
- **트레이드오프**: 어댑터 계층 코드가 늘어납니다. UI, GSMTC 연동, 셸 연동은 빌드 성공과 수동 확인으로만 검증합니다.
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
  - `TreatWarningsAsErrors`. NuGet 취약점 감사 경고 NU1901~NU1904는 경고로 남깁니다.
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

- **상태**: 채택(제출 도구는 확인 후 확정)
- **결정**: GitHub Actions에서 `vX.Y.Z` 태그를 push하면 빌드, 테스트, 패키지 버전 `X.Y.Z.0`의 MSIX 생성, Store 제출을 차례로 진행하고, 인증을 통과하면 자동으로 게시합니다.
- **이유**: 태그를 올리는 것 자체가 출시 결정이므로 수작업을 줄입니다.
- **트레이드오프**: 잘못 올린 태그도 인증만 통과하면 게시됩니다. Entra ID 자격 증명을 관리해야 합니다. 최초 제출은 Partner Center에서 직접 해야 할 수 있습니다.
- **하네스에 미치는 영향**: 자격 증명과 패키지 식별 정보를 워크플로나 저장소에 하드코딩하지 마세요. GitHub Secrets만 씁니다.
