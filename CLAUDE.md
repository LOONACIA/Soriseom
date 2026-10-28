# CLAUDE.md

Soriseom(소리섬) 저장소의 코딩 규칙입니다. Claude Code가 읽고, Codex는 `AGENTS.md`를 거쳐 읽습니다.

## 먼저 읽을 문서

- `docs/PRD.md`: 무엇을 만들고 무엇을 만들지 않는지, 기능별 완료 기준
- `docs/ARCHITECTURE.md`: 디렉토리 구조, 레이어 규칙, 데이터 흐름, 구현 전에 확인할 것
- `docs/ADR.md`: 되돌리기 어려운 기술 결정과 허용된 외부 의존성

## 언어

- 코드 식별자, 주석, 커밋 메시지는 영어로 씁니다.
- 설계 문서(`docs/`), 이 파일, 하네스 계획은 한국어로 씁니다.
- 사용자에게 보이는 문자열은 코드에 하드코딩하지 않습니다. `.resw` 리소스에 en-US와 ko-KR을 함께 추가합니다.

## 커밋

- Conventional Commits: `<type>(<scope>): <subject>`. subject는 영어 명령형, 소문자로 시작, 마침표 없음.
- scope 예: `core`, `app`, `tests`, `ci`, `docs`, `build`.

## 명령어

저장소 루트에서 실행합니다. 솔루션 뼈대(`Soriseom.slnx`, `global.json`)가 생긴 뒤부터 동작합니다. 2026-10-29에 같은 구조의 임시 솔루션으로 검증했습니다.

### 검사: 모든 변경이 통과해야 함

| 목적 | 명령 |
|---|---|
| 빌드 | `dotnet build Soriseom.slnx -p:Platform=x64` |
| 테스트 | `dotnet test --project tests/Soriseom.Core.Tests` |
| 포맷 검사 | `dotnet format Soriseom.slnx --verify-no-changes` |

- 경고가 하나라도 있으면 빌드가 실패합니다.
- 포맷 검사가 실패하면 먼저 `dotnet format Soriseom.slnx`로 자동 수정한 뒤 다시 검사합니다. 자동으로 고쳐지지 않는 위반만 직접 고칩니다.

### 그 밖의 명령

| 목적 | 명령 |
|---|---|
| 테스트 메서드 하나 | `dotnet test --project tests/Soriseom.Core.Tests --filter-method "*.<클래스>.<메서드>"` |
| 테스트 클래스 하나 | `dotnet test --project tests/Soriseom.Core.Tests --filter-class "Soriseom.Core.Tests.<클래스>"` |
| 포맷 자동 수정 | `dotnet format Soriseom.slnx` |
| NuGet 패키지 추가 | `dotnet add <프로젝트 경로> package <패키지> --version <버전>` |
| 취약 패키지 점검 | `dotnet package list --project Soriseom.slnx --vulnerable` |
| 로컬 MSIX 생성(Debug, 서명 없음) | `dotnet build src/Soriseom.App -p:Platform=x64 -p:GenerateAppxPackageOnBuild=true -p:AppxPackageSigningEnabled=false` |

### 주의

- WinUI 앱이 포함된 빌드에는 항상 `-p:Platform=x64`를 붙입니다. 빼면 App 프로젝트는 `win-AnyCPU.pubxml`을 찾지 못해 실패하고, 솔루션은 ARM64로 빌드됩니다.
- 테스트는 Microsoft Testing Platform으로 돌아갑니다(`global.json`의 `test.runner`, xUnit v3에 필요). 필터는 VSTest의 `--filter`가 아니라 `--filter-method`, `--filter-class`를 씁니다. 테스트가 실패하면 종료 코드가 0이 아닙니다.
- 패키지를 추가하면 버전은 `Directory.Packages.props`에 자동으로 들어가고 `.csproj`에는 버전 없는 참조만 남습니다. `docs/ADR.md`에 없는 패키지는 추가하지 않습니다.
- MSIX는 `src/Soriseom.App/AppPackages/`에 생깁니다(git에서 무시됨).
- 앱을 실행하지 마세요(`dotnet run` 포함). 트레이에 상주하는 GUI 프로세스라 스스로 끝나지 않고, 패키지 앱이라 실행하면 개발용 패키지가 시스템에 등록됩니다. 실행 확인은 사람이 Visual Studio에서 합니다.
- Release 빌드는 아직 실패합니다. 트리밍 경고(IL2104)가 오류로 처리되기 때문이며, 해결 방법은 `docs/ARCHITECTURE.md` "구현 전에 확인할 것"에 있습니다.

## C# 규칙

- .NET 10, C# 14(SDK 기본 `LangVersion`). `Nullable`과 `ImplicitUsings`를 켭니다.
- 공통 빌드 설정은 `Directory.Build.props`, NuGet 버전은 `Directory.Packages.props`(Central Package Management), 스타일과 분석기 규칙은 루트 `.editorconfig`에 둡니다. 개별 `.csproj`에 같은 설정을 중복해서 넣지 않습니다.
- 경고는 오류로 처리합니다. 예외는 NuGet 취약점 감사 경고(NU1901~NU1904)뿐입니다.
- 분석기는 .NET 내장 분석기(`EnforceCodeStyleInBuild`)와 StyleCop.Analyzers(1.3 이상)를 씁니다.
- 경고를 `#pragma warning disable`나 `[SuppressMessage]`로 숨기지 않습니다. 규칙이 프로젝트에 맞지 않으면 `.editorconfig`에서 사유 주석과 함께 끄고, 그 변경은 별도로 리뷰받습니다.
- 이름 규칙
  - private 필드: `_camelCase`
  - 타입, 메서드, 속성, 이벤트: PascalCase
  - 지역 변수, 매개변수: camelCase
  - 인터페이스는 `I` 접두사, 비동기 메서드는 `Async` 접미사
  - `this.`를 붙이지 않습니다.
- 파일 하나에 타입 하나를 두고, 파일 이름은 타입 이름과 같게 합니다. file-scoped namespace를 쓰고, `using`은 namespace 밖에 둡니다.
- 파일 머리에 라이선스 헤더를 넣지 않습니다.
- XML 문서 주석(`///`)은 필수가 아닙니다. 필요한 곳에만 쓰고, 쓴 주석은 형식 규칙을 지킵니다.

## 구조 규칙

자세한 내용은 `docs/ARCHITECTURE.md`에 있습니다. 어기기 쉬운 것만 여기 적습니다.

- `Soriseom.Core`는 `net10.0`입니다. `Windows.*`, `Microsoft.UI.*`, App 프로젝트를 참조하지 않습니다.
- `Soriseom.Core`는 타이머, 스레드, `DateTime.Now`/`DateTimeOffset.Now`를 직접 쓰지 않습니다. 현재 시각은 인자로 받습니다.
- GSMTC(`Windows.Media.Control`)는 App의 어댑터 한 곳에서만 다룹니다.
- ViewModel은 App에 두고 CommunityToolkit.Mvvm(`[ObservableProperty]`, `[RelayCommand]`)으로 씁니다. `INotifyPropertyChanged`를 직접 구현하지 않습니다. 기본값과 허용 범위 같은 규칙은 Core의 설정 모델에 둡니다.
- XAML 바인딩은 `x:Bind`를 씁니다.
- `docs/ADR.md`에 없는 NuGet 패키지를 추가하지 않습니다.

## 테스트

- xUnit v3를 씁니다. 테스트는 `tests/Soriseom.Core.Tests`에만 둡니다.
- Core에 판단 로직을 추가하거나 바꾸면 같은 변경에서 테스트도 추가하거나 바꿉니다.
- App(UI, GSMTC 어댑터, 셸 연동)은 빌드 성공과 수동 확인으로 검증합니다.
