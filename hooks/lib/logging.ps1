function Get-LoggingEnabled {
  try {
    if ($env:CODEX_APPROVAL_TOAST_LOG) {
      return $env:CODEX_APPROVAL_TOAST_LOG -match '^(1|true|yes|on)$'
    }

    if (Test-Path $script:ToastConfigPath) {
      $config = Get-Content -Raw -Path $script:ToastConfigPath | ConvertFrom-Json
      return [bool]$config.logging
    }
  } catch {}

  return $false
}

$script:LoggingEnabled = Get-LoggingEnabled

function Write-DebugLog {
  param([string]$Message)

  if (-not $script:LoggingEnabled) {
    return
  }

  try {
    $timestamp = (Get-Date).ToString("o")
    "$timestamp $Message" | Add-Content -Path $script:DebugLogPath -Encoding UTF8
  } catch {}
}
