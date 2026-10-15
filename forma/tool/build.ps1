param([ValidateSet('Apk','Bundle','Preview','Check')][string]$Task='Check')
$ErrorActionPreference='Stop'
$taskProject=Split-Path -Parent $PSScriptRoot
$taskFlutter=(Get-Command flutter -ErrorAction Stop).Source
$taskPreviousSigning=$env:FORMA_LOCAL_SIGNING
Push-Location $taskProject
try {
    & $taskFlutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
    switch ($Task) {
        'Check' {
            & $taskFlutter analyze
            if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
            & $taskFlutter test
        }
        'Apk' {
            $env:FORMA_LOCAL_SIGNING='true'
            & $taskFlutter build apk --release
            if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
            New-Item -ItemType Directory -Path 'dist' -Force | Out-Null
            Copy-Item -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' -Destination 'dist\El-Thanawiya.apk'
        }
        'Bundle' {
            if (-not (Test-Path -LiteralPath 'android\key.properties')) { throw 'Configure your own upload signing key using android/key.properties.example first.' }
            Remove-Item Env:FORMA_LOCAL_SIGNING -ErrorAction SilentlyContinue
            & $taskFlutter build appbundle --release
        }
        'Preview' {
            & $taskFlutter build web --release --dart-define=DEMO=true --no-web-resources-cdn --base-href /app/ --output build/preview/app
            if ($LASTEXITCODE -ne 0) { throw 'Web preview build failed.' }
            Copy-Item -LiteralPath 'tool\preview.html' -Destination 'build\preview\index.html'
            Write-Host 'Serve build/preview over HTTP. This preview uses illustrative sample data.'
        }
    }
    if ($LASTEXITCODE -ne 0) { throw 'The requested task failed.' }
} finally {
    $env:FORMA_LOCAL_SIGNING=$taskPreviousSigning
    Pop-Location
}
