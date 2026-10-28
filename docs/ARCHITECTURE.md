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

- **팝업 창**: 테두리 없음, 항상 위, 활성화하지 않음(포커스 유지), 작업 표시줄과 Alt+Tab에서 제외, 클릭 통과, Acrylic 배경. 위치는 주 모니터 작업 영역 기준 6곳이고 DPI 배율을 반영합니다.
- **트레이**: H.NotifyIcon.WinUI. 왼쪽 클릭은 설정 창, 오른쪽 클릭은 메뉴(설정, 종료)입니다.
- **단일 인스턴스**: Windows App SDK의 `AppInstance`로 두 번째 실행을 기존 인스턴스로 넘기고, 기존 인스턴스는 설정 창을 엽니다.
- **자동 실행**: MSIX `StartupTask`. 첫 실행 때 활성화를 요청하고, 설정에서 켜고 끕니다. 자동 실행으로 시작됐는지 구분해서 창을 열지 정합니다.
- **전체화면 감지**: `SHQueryUserNotificationState`를 써서 Windows 알림과 같은 기준으로 판단합니다.

## 횡단 관심사

- **에러 처리**: GSMTC, 썸네일, 셸 API가 실패해도 앱이 종료되지 않습니다. 썸네일을 못 읽으면 음표 아이콘을 쓰고, 세션 정보를 못 읽으면 그 팝업만 건너뜁니다. 예외는 디버그 출력에 남깁니다.
- **로깅**: `System.Diagnostics.Debug` 출력만 씁니다. 파일 로그와 네트워크 전송은 없습니다.
- **설정 저장**: `ApplicationData.Current.LocalSettings`. 키 이름은 한 곳에 상수로 모읍니다.
- **현지화**: `Strings/en-US/Resources.resw`, `Strings/ko-KR/Resources.resw`. 언어를 직접 고르면 `ApplicationLanguages.PrimaryLanguageOverride`로 바꿉니다.
- **의존성**: Central Package Management로 버전을 고정합니다. 허용 목록은 `docs/ADR.md`의 "원칙"에 있습니다.
- **품질 게이트**: `Directory.Build.props`에서 Nullable, `TreatWarningsAsErrors`(NU1901~NU1904 제외), `EnforceCodeStyleInBuild`, `GenerateDocumentationFile`(CS1591 끔)을 켭니다. StyleCop 규칙 조정은 `docs/ADR.md` ADR-006을 따릅니다.
- **CI**: GitHub Actions(Windows runner). push와 PR에서 빌드, 테스트, 포맷 검사를 돌립니다. `vX.Y.Z` 태그를 push하면 패키지 버전 `X.Y.Z.0`으로 MSIX를 만들어 Store에 제출하고, 인증을 통과하면 자동으로 게시합니다.

## 구현 전에 확인할 것

관련 스텝을 계획하기 전에 확인하고, 결과를 이 문서나 ADR에 반영합니다.

- [ ] Release 빌드와 패키징: 템플릿은 Release에서 트리밍(`PublishTrimmed`)을 켜는데, `Microsoft.Windows.SDK.NET`과 `WinRT.Runtime`의 트리밍 경고(IL2104)가 경고=오류 설정 때문에 빌드를 실패시킵니다. 트리밍을 끌지, IL2104만 오류에서 뺄지 CI 스텝 전에 정합니다.
- [ ] 패키지 앱에서 GSMTC를 쓰는 데 별도 capability가 필요한지
- [ ] WinUI 3 창에 Acrylic 배경과 클릭 통과(확장 창 스타일)를 함께 적용할 수 있는지
- [ ] Windows 방해 금지 모드를 감지할 공식 API가 있는지. 없으면 이 기능은 빼고 PRD를 고칩니다.
- [ ] 언어 변경이 재시작 없이 반영되는지
- [ ] Store 자동 제출 방식(msstore CLI와 Entra ID 앱 연동), 최초 제출을 수동으로 해야 하는지

