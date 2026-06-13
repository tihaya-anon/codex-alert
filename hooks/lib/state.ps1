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

  return Join-Path $script:OverlayStateDir "$NotificationId.json"
}

function Get-ApprovalStates {
  $states = @()

  try {
    if (Test-Path $script:LegacyApprovalStatePath) {
      $legacyState = Get-Content -Raw -Path $script:LegacyApprovalStatePath | ConvertFrom-Json
      $legacyState | Add-Member -NotePropertyName notification_id -NotePropertyValue $script:LegacyApprovalNotificationId -Force
      $legacyState | Add-Member -NotePropertyName state_path -NotePropertyValue $script:LegacyApprovalStatePath -Force
      $states += $legacyState
    }
  } catch {
    Write-DebugLog "legacy state read failed: $($_.Exception.Message)"
  }

  try {
    if (Test-Path $script:OverlayStateDir) {
      Get-ChildItem -Path $script:OverlayStateDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
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

  $approvalStates = @($States | Where-Object {
    $itemKind = ""
    try { $itemKind = [string]$_.item_kind } catch {}
    if (-not $itemKind) {
      try { $itemKind = [string]$_.ItemKind } catch {}
    }
    $itemKind -ne "session"
  })
  if ($approvalStates.Count -eq 0) {
    return @()
  }

  $normalizedCommand = Normalize-ApprovalCommand -Command $Command
  $candidateStates = @()

  if ($Tool -or $Cwd -or $normalizedCommand) {
    $candidateStates = @($approvalStates | Where-Object {
      [string]$_.tool -eq $Tool -and
      [string]$_.cwd -eq $Cwd -and
      [string]$_.command -eq $normalizedCommand
    })

    if ($candidateStates.Count -eq 0 -and $normalizedCommand) {
      $candidateStates = @($approvalStates | Where-Object { [string]$_.command -eq $normalizedCommand })
    }

    if ($candidateStates.Count -eq 0 -and $Tool) {
      $candidateStates = @($approvalStates | Where-Object { [string]$_.tool -eq $Tool })
    }
  }

  if ($candidateStates.Count -eq 0) {
    $candidateStates = @($approvalStates)
  }

  return @($candidateStates | Sort-Object -Property timestamp | Select-Object -First 1)
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
    New-Item -ItemType Directory -Path $script:OverlayStateDir -Force | Out-Null
    $state = @{
      notification_id = $NotificationId
      timestamp = (Get-Date).ToString("o")
      item_kind = "approval"
      tool = $Tool
      cwd = $Cwd
      command = (Normalize-ApprovalCommand -Command $Command)
    } | ConvertTo-Json -Compress

    $state | Set-Content -Path (Get-ApprovalStatePath -NotificationId $NotificationId) -Encoding UTF8
  } catch {
    Write-DebugLog "state write failed: $($_.Exception.Message)"
  }
}

function Write-SessionState {
  param([string]$Cwd)

  try {
    New-Item -ItemType Directory -Path $script:OverlayStateDir -Force | Out-Null
    Get-ChildItem -Path $script:OverlayStateDir -Filter "$($script:NotificationPrefixSessionEnd)-*.json" -File -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue

    $sessionNotificationId = New-NotificationId -Prefix $script:NotificationPrefixSessionEnd
    $state = @{
      notification_id = $sessionNotificationId
      timestamp = (Get-Date).ToString("o")
      item_kind = "session"
      tool = "Stop"
      cwd = $Cwd
      command = "Codex turn finished"
    } | ConvertTo-Json -Compress

    $statePath = Join-Path $script:OverlayStateDir "$sessionNotificationId.json"
    $state | Set-Content -Path $statePath -Encoding UTF8
    Write-DebugLog "session state written path=$statePath"
  } catch {
    Write-DebugLog "session state write failed: $($_.Exception.Message)"
  }
}

function Clear-SessionStates {
  try {
    if (Test-Path $script:OverlayStateDir) {
      Get-ChildItem -Path $script:OverlayStateDir -Filter "$($script:NotificationPrefixSessionEnd)-*.json" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
      Write-DebugLog "session states cleared"
    }
  } catch {
    Write-DebugLog "session state clear failed: $($_.Exception.Message)"
  }
}

function Test-ApprovalState {
  if (Test-Path $script:LegacyApprovalStatePath) {
    return $true
  }

  if (Test-Path $script:OverlayStateDir) {
    return [bool](Get-ChildItem -Path $script:OverlayStateDir -Filter "$($script:NotificationPrefixApproval)-*.json" -File -ErrorAction SilentlyContinue | Select-Object -First 1)
  }

  return $false
}
