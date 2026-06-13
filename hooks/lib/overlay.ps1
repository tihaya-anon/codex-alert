function Start-OverlayProcess {
  param(
    [string]$StateDir,
    [ValidateSet("approval", "session")]
    [string]$Kind
  )

  try {
    if (-not (Test-Path $script:OverlayScriptPath)) {
      Write-DebugLog "overlay missing path=$script:OverlayScriptPath"
      return
    }

    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    $powershellPath = Join-Path $PSHOME "powershell.exe"
    $arguments = @(
      "-NoProfile",
      "-STA",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      $script:OverlayScriptPath,
      "-StateDir",
      $StateDir,
      "-LogPath",
      $script:DebugLogPath,
      "-IconPath",
      $script:OverlayIconPath,
      "-Kind",
      $Kind
    )

    Start-Process -FilePath $powershellPath -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    Write-DebugLog "overlay start requested path=$script:OverlayScriptPath stateDir=$StateDir kind=$Kind"
  } catch {
    Write-DebugLog "overlay start failed: $($_.Exception.Message)"
  }
}
