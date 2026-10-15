param([string]$Python='python', [string]$Output='runs/reproduction', [ValidateSet('auto','cpu','cuda')][string]$Device='auto')
$ErrorActionPreference='Stop'
$taskPython=(Get-Command $Python -ErrorAction Stop).Source
$taskOutput=if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $PSScriptRoot $Output }
& $taskPython (Join-Path $PSScriptRoot 'prepare_data.py')
if ($LASTEXITCODE -ne 0) { throw 'Data preparation failed.' }
& $taskPython (Join-Path $PSScriptRoot 'train.py') --output $taskOutput --device $Device
if ($LASTEXITCODE -ne 0) { throw 'Training failed.' }
