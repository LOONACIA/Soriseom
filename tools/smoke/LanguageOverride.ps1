# Reads or sets ApplicationLanguages.PrimaryLanguageOverride. Smoke.ps1 runs this inside the package,
# because the override is kept per package and only a process with package identity can reach it.
# Windows PowerShell 5.1 only: pwsh 7 has no WinRT projection.
param(
    [string] $ResultPath,
    [string] $Set
)

$ErrorActionPreference = 'Stop'

try {
    $languages = [Windows.Globalization.ApplicationLanguages, Windows.Globalization, ContentType = WindowsRuntime]
    if ($PSBoundParameters.ContainsKey('Set')) { $languages::PrimaryLanguageOverride = $Set }
    Set-Content -Path $ResultPath -Value ("=" + $languages::PrimaryLanguageOverride) -Encoding UTF8
} catch {
    Set-Content -Path $ResultPath -Value ("!" + $_) -Encoding UTF8
}
