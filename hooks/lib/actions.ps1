function Show-ApprovalOverlay {
  param([pscustomobject]$Context)

  $notificationId = New-NotificationId -Prefix $script:NotificationPrefixApproval
  $displayCommand = Normalize-ApprovalCommand -Command $Context.Command
  if ($displayCommand.Length -gt 120) {
    $displayCommand = $displayCommand.Substring(0, 117) + "..."
  }

  $title = if ($displayCommand) { $displayCommand } else { "Codex approval requested" }
  $contextText = "$($Context.Cwd) | $($Context.Tool)"

  Write-DebugLog "approval id=$notificationId text=$title || $contextText"
  Write-ApprovalState -NotificationId $notificationId -Tool $Context.Tool -Cwd $Context.Cwd -Command $Context.Command
  Start-OverlayProcess -StateDir $script:OverlayStateDir -Kind "approval"
}

function Clear-ApprovalOverlay {
  param([pscustomobject]$Context)

  if (-not (Test-ApprovalState)) {
    return
  }

  Write-DebugLog "clear requested tool=$($Context.Tool) cwd=$($Context.Cwd) command=$(Normalize-ApprovalCommand -Command $Context.Command)"
  $states = @(Get-ApprovalStates)
  $statesToClear = @(Select-ApprovalStatesForClear -States $states -Tool $Context.Tool -Cwd $Context.Cwd -Command $Context.Command)
  Remove-ApprovalStates -States $statesToClear

  if (Test-ApprovalState) {
    Start-OverlayProcess -StateDir $script:OverlayStateDir -Kind "approval"
  }
}

function Show-SessionOverlay {
  param([pscustomobject]$Context)

  Write-SessionState -Cwd $Context.Cwd
  Start-OverlayProcess -StateDir $script:OverlayStateDir -Kind "approval"
}
