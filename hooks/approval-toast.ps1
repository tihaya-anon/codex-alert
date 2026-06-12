param(
  [switch]$Clear,
  [switch]$SessionEnd
)

$approvalNotificationPrefix = "codex-approval"
$sessionEndNotificationPrefix = "codex-session-end"
$legacyApprovalNotificationId = "codex-approval"
$debugPath = Join-Path $env:TEMP "codex-approval-toast-debug.log"
$overlayPath = Join-Path $PSScriptRoot "approval-overlay.ps1"
$overlayIconPath = Join-Path $PSScriptRoot "codex-approval-toast-icon.png"
$stateDir = Join-Path $PSScriptRoot "approval-toast-active"
$sessionStateDir = Join-Path $PSScriptRoot "session-toast-active"
$legacyStatePath = Join-Path $PSScriptRoot "approval-toast-active.json"
$configPath = Join-Path $PSScriptRoot "approval-toast-config.json"

function Get-LoggingEnabled {
  try {
    if ($env:CODEX_APPROVAL_TOAST_LOG) {
      return $env:CODEX_APPROVAL_TOAST_LOG -match '^(1|true|yes|on)$'
    }

    if (Test-Path $configPath) {
      $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
      return [bool]$config.logging
    }
  } catch {}

  return $false
}

$loggingEnabled = Get-LoggingEnabled

function Write-DebugLog {
  param([string]$Message)
  if (-not $loggingEnabled) {
    return
  }

  try {
    $timestamp = (Get-Date).ToString("o")
    "$timestamp $Message" | Add-Content -Path $debugPath -Encoding UTF8
  } catch {}
}

function Start-ApprovalOverlay {
  param(
    [string]$OverlayStateDir = $stateDir,
    [string]$Kind = "approval"
  )

  try {
    if (-not (Test-Path $overlayPath)) {
      Write-DebugLog "overlay missing path=$overlayPath"
      return
    }

    New-Item -ItemType Directory -Path $OverlayStateDir -Force | Out-Null
    $powershellPath = Join-Path $PSHOME "powershell.exe"
    $arguments = @(
      "-NoProfile",
      "-STA",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      $overlayPath,
      "-StateDir",
      $OverlayStateDir,
      "-LogPath",
      $debugPath,
      "-IconPath",
      $overlayIconPath,
      "-Kind",
      $Kind
    )

    Start-Process -FilePath $powershellPath -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    Write-DebugLog "overlay start requested path=$overlayPath stateDir=$OverlayStateDir kind=$Kind"
  } catch {
    Write-DebugLog "overlay start failed: $($_.Exception.Message)"
  }
}

function Normalize-ApprovalCommand {
  param([string]$Command)
  if (-not $Command) {
    return ""
  }

  return ($Command -replace '\s+', ' ').Trim()
}

function New-NotificationId {
  param([string]$Prefix)

  $timestamp = (Get-Date).ToString("yyyyMMddHHmmssfff")
  $nonce = [Guid]::NewGuid().ToString("N").Substring(0, 8)
  return "$Prefix-$timestamp-$nonce"
}

function Get-ApprovalStatePath {
  param([string]$NotificationId)
  return (Join-Path $stateDir "$NotificationId.json")
}

function Get-ApprovalStates {
  $states = @()

  try {
    if (Test-Path $legacyStatePath) {
      $legacy = Get-Content -Raw -Path $legacyStatePath | ConvertFrom-Json
      $legacy | Add-Member -NotePropertyName notification_id -NotePropertyValue $legacyApprovalNotificationId -Force
      $legacy | Add-Member -NotePropertyName state_path -NotePropertyValue $legacyStatePath -Force
      $states += $legacy
    }
  } catch {
    Write-DebugLog "legacy state read failed: $($_.Exception.Message)"
  }

  try {
    if (Test-Path $stateDir) {
      Get-ChildItem -Path $stateDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
        ForEach-Object {
          try {
            $state = Get-Content -Raw -Path $_.FullName | ConvertFrom-Json
            if (-not $state.notification_id) {
              $state | Add-Member -NotePropertyName notification_id -NotePropertyValue $_.BaseName -Force
            }
            $state | Add-Member -NotePropertyName state_path -NotePropertyValue $_.FullName -Force
            $states += $state
          } catch {
            Write-DebugLog "state read failed path=$($_.FullName): $($_.Exception.Message)"
          }
        }
    }
  } catch {
    Write-DebugLog "state list failed: $($_.Exception.Message)"
  }

  return $states
}

function Select-ApprovalStatesForClear {
  param(
    [object[]]$States,
    [string]$Tool,
    [string]$Cwd,
    [string]$Command
  )

  if (-not $States -or $States.Count -eq 0) {
    return @()
  }

  $normalizedCommand = Normalize-ApprovalCommand -Command $Command
  $candidates = @()

  if ($Tool -or $Cwd -or $normalizedCommand) {
    $candidates = @($States | Where-Object {
      [string]$_.tool -eq $Tool -and
      [string]$_.cwd -eq $Cwd -and
      [string]$_.command -eq $normalizedCommand
    })

    if ($candidates.Count -eq 0 -and $normalizedCommand) {
      $candidates = @($States | Where-Object { [string]$_.command -eq $normalizedCommand })
    }

    if ($candidates.Count -eq 0 -and $Tool) {
      $candidates = @($States | Where-Object { [string]$_.tool -eq $Tool })
    }
  }

  if ($candidates.Count -eq 0) {
    $candidates = @($States)
  }

  return @($candidates | Sort-Object -Property timestamp | Select-Object -First 1)
}

function Remove-ApprovalStates {
  param([object[]]$States)

  try {
    foreach ($state in @($States)) {
      try {
        if ($state.state_path) {
          Remove-Item -Path $state.state_path -Force -ErrorAction SilentlyContinue
          Write-DebugLog "state cleared path=$($state.state_path)"
        }
      } catch {
        Write-DebugLog "state clear failed path=$($state.state_path): $($_.Exception.Message)"
      }
    }
  } catch {
    Write-DebugLog "state clear failed: $($_.Exception.Message)"
  }
}

function Write-ApprovalState {
  param(
    [string]$NotificationId,
    [string]$Tool,
    [string]$Cwd,
    [string]$Command
  )

  try {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $statePath = Get-ApprovalStatePath -NotificationId $NotificationId
    $state = @{
      notification_id = $NotificationId
      timestamp = (Get-Date).ToString("o")
      tool = $Tool
      cwd = $Cwd
      command = (Normalize-ApprovalCommand -Command $Command)
    } | ConvertTo-Json -Compress

    $state | Set-Content -Path $statePath -Encoding UTF8
    Write-DebugLog "state written path=$statePath"
  } catch {
    Write-DebugLog "state write failed: $($_.Exception.Message)"
  }
}

function Write-SessionState {
  param([string]$Cwd)

  try {
    New-Item -ItemType Directory -Path $sessionStateDir -Force | Out-Null
    Get-ChildItem -Path $sessionStateDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue

    $sessionNotificationId = New-NotificationId -Prefix $sessionEndNotificationPrefix
    $statePath = Join-Path $sessionStateDir "$sessionNotificationId.json"
    $state = @{
      notification_id = $sessionNotificationId
      timestamp = (Get-Date).ToString("o")
      tool = "Stop"
      cwd = $Cwd
      command = "Codex turn finished"
    } | ConvertTo-Json -Compress

    $state | Set-Content -Path $statePath -Encoding UTF8
    Write-DebugLog "session state written path=$statePath"
  } catch {
    Write-DebugLog "session state write failed: $($_.Exception.Message)"
  }
}

function Test-ApprovalState {
  if (Test-Path $legacyStatePath) {
    return $true
  }

  if (Test-Path $stateDir) {
    return [bool](Get-ChildItem -Path $stateDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Select-Object -First 1)
  }

  return $false
}

function ConvertFrom-JsonStringLiteral {
  param([string]$Value)
  try {
    $json = "{""value"":""$Value""}"
    return ($json | ConvertFrom-Json).value
  } catch {
    return ($Value -replace '\\n', "`n" -replace '\\"', '"' -replace '\\\\', '\')
  }
}

function Format-CodexWorkspacePath {
  param([string]$Cwd)

  if (-not $Cwd) {
    $Cwd = $env:CODEX_HOOK_CWD
  }

  if (-not $Cwd) {
    $Cwd = $env:PWD
  }

  if (-not $Cwd) {
    return "unknown project"
  }

  $wslHome = $env:HOME
  if (-not $wslHome -and $Cwd -match '^(/home/[^/]+)($|/)') {
    $wslHome = $Matches[1]
  }

  if ($wslHome -and $Cwd.StartsWith($wslHome)) {
    return "~" + $Cwd.Substring($wslHome.Length)
  }

  return $Cwd
}

function Get-CodexWorkspacePathFromValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return ""
  }

  if ($Value -is [string]) {
    return $Value
  }

  foreach ($propertyName in @("cwd", "path", "root")) {
    try {
      $propertyValue = $Value.$propertyName
      if ($propertyValue -is [string] -and $propertyValue) {
        return $propertyValue
      }
    } catch {}
  }

  return ""
}

function Get-HookContext {
  param([string]$InputJson)

  $tool = "approval"
  $cwd = ""
  $cmd = ""

  try {
    $data = $InputJson | ConvertFrom-Json
    $tool = $data.tool_name
    if (-not $tool) { $tool = "approval" }

    $cwd = $data.cwd
    if (-not $cwd) { $cwd = $data.workspace_root }
    if (-not $cwd -and $data.workspace) {
      $cwd = Get-CodexWorkspacePathFromValue -Value $data.workspace
    }
    if (-not $cwd -and $data.workspace_roots -and $data.workspace_roots.Count -gt 0) {
      $cwd = Get-CodexWorkspacePathFromValue -Value $data.workspace_roots[0]
    }
    if (-not $cwd -and $data.session) {
      $cwd = Get-CodexWorkspacePathFromValue -Value $data.session
    }

    $toolInput = $data.tool_input
    $cmd = $toolInput.command
    if (-not $cmd) { $cmd = $toolInput.cmd }
    if (-not $cmd -and $null -ne $toolInput) {
      $cmd = $toolInput | ConvertTo-Json -Compress -Depth 8
    }
    if (-not $cmd) { $cmd = "" }
  } catch {
    Write-DebugLog "payload parse failed: $($_.Exception.Message)"

    $toolMatch = [regex]::Match($InputJson, '"tool_name"\s*:\s*"((?:\\.|[^"\\])*)"')
    if ($toolMatch.Success) {
      $tool = ConvertFrom-JsonStringLiteral $toolMatch.Groups[1].Value
    }

    $cwdMatch = [regex]::Match($InputJson, '"cwd"\s*:\s*"((?:\\.|[^"\\])*)"')
    if ($cwdMatch.Success) {
      $cwd = ConvertFrom-JsonStringLiteral $cwdMatch.Groups[1].Value
    }

    $cmdMatch = [regex]::Match($InputJson, '"command"\s*:\s*"((?:\\.|[^"\\])*)"')
    if ($cmdMatch.Success) {
      $cmd = ConvertFrom-JsonStringLiteral $cmdMatch.Groups[1].Value
    }
  }

  $cwd = Format-CodexWorkspacePath -Cwd $cwd

  return [pscustomobject]@{
    Tool = $tool
    Cwd = $cwd
    Command = $cmd
  }
}

if ($Clear) {
  $inputJson = [Console]::In.ReadToEnd()
  Write-DebugLog "payload=$inputJson"

  if (-not (Test-ApprovalState)) {
    exit 0
  }

  $context = Get-HookContext -InputJson $inputJson
  Write-DebugLog "clear requested tool=$($context.Tool) cwd=$($context.Cwd) command=$(Normalize-ApprovalCommand -Command $context.Command)"

  $states = @(Get-ApprovalStates)
  $statesToClear = @(Select-ApprovalStatesForClear `
    -States $states `
    -Tool $context.Tool `
    -Cwd $context.Cwd `
    -Command $context.Command)

  Remove-ApprovalStates -States $statesToClear
  if (Test-ApprovalState) {
    Start-ApprovalOverlay
  }
  exit 0
}

$inputJson = [Console]::In.ReadToEnd()
Write-DebugLog "payload=$inputJson"

$context = Get-HookContext -InputJson $inputJson
$tool = $context.Tool
$cwd = $context.Cwd
$cmd = $context.Command

if ($SessionEnd) {
  Write-SessionState -Cwd $cwd
  Start-ApprovalOverlay -OverlayStateDir $sessionStateDir -Kind "session"
  exit 0
}

$notificationId = New-NotificationId -Prefix $approvalNotificationPrefix
$displayCmd = Normalize-ApprovalCommand -Command $cmd
if ($displayCmd.Length -gt 120) {
  $displayCmd = $displayCmd.Substring(0, 117) + "..."
}

$title = if ($displayCmd) { $displayCmd } else { "Codex approval requested" }
$contextText = "$cwd | $tool"

Write-DebugLog "approval id=$notificationId text=$title || $contextText"
Write-ApprovalState -NotificationId $notificationId -Tool $tool -Cwd $cwd -Command $cmd
Start-ApprovalOverlay
exit 0
