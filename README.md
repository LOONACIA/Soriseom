# Soriseom (소리섬)

[한국어](#한국어) | [English](#english)

## 한국어

곡이 바뀔 때 지금 재생 중인 음악을 화면에 잠깐 보여주는 Windows 앱입니다.

> 개발 중입니다. 아직 설치할 수 있는 버전이 없습니다.

### 기능 (예정)

- 곡이 바뀌면 화면 위쪽 가운데에 제목, 아티스트, 앨범아트를 몇 초간 표시
- Windows 미디어 세션(GSMTC)을 사용해 Spotify, 브라우저(YouTube, YouTube Music) 등 미디어 세션을 지원하는 앱을 플레이어 구분 없이 지원
- 팝업 위 클릭이 뒤쪽 창으로 통과되어 작업을 방해하지 않음
- 전체화면 앱 사용 중에는 표시하지 않음
- 앱별 켜기/끄기, 표시 시간, 표시 위치 설정
- 트레이 상주, Windows 로그인 시 자동 실행
- 사용 데이터를 수집하지 않음

### 요구 사항

- Windows 10 버전 1809 이상 또는 Windows 11

### 배포

Microsoft Store로 배포할 예정입니다.

### 기술 스택

C# / .NET 10, WinUI 3 (Windows App SDK), MSIX

### 라이선스

[MIT](LICENSE)

## English

A Windows app that briefly shows what's playing whenever the track changes.

> Under development. No installable release yet.

### Features (planned)

- Shows title, artist, and album art at the top center of the screen for a few seconds when the track changes
- Uses Windows media sessions (GSMTC), so it works with any app that reports to them, such as Spotify and browsers (YouTube, YouTube Music)
- Click-through popup that never gets in your way
- Stays hidden while a fullscreen app is running
- Per-app on/off, display duration, and position settings
- Lives in the system tray and starts with Windows
- Collects no usage data

### Requirements

- Windows 10 version 1809 or later, or Windows 11

### Distribution

Will be distributed through the Microsoft Store.

### Tech stack

C# / .NET 10, WinUI 3 (Windows App SDK), MSIX

### License

[MIT](LICENSE)
