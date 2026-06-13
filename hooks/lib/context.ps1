function ConvertFrom-JsonStringLiteral {
  param([string]$Value)

  try {
    $json = "{""value"":""$Value""}"
    return ($json | ConvertFrom-Json).value
  } catch {
    return ($Value -replace '\\n', "`n" -replace '\\"', '"' -replace '\\\\', '\')
  }
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

function Get-HookContext {
  param([string]$InputJson)

  $tool = "approval"
  $cwd = ""
  $commandText = ""

  try {
    $data = $InputJson | ConvertFrom-Json
    $tool = $data.tool_name
    if (-not $tool) {
      $tool = "approval"
    }

    $cwd = $data.cwd
    if (-not $cwd) {
      $cwd = $data.workspace_root
    }
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
    $commandText = $toolInput.command
    if (-not $commandText) {
      $commandText = $toolInput.cmd
    }
    if (-not $commandText -and $null -ne $toolInput) {
      $commandText = $toolInput | ConvertTo-Json -Compress -Depth 8
    }
    if (-not $commandText) {
      $commandText = ""
    }
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

    $commandMatch = [regex]::Match($InputJson, '"command"\s*:\s*"((?:\\.|[^"\\])*)"')
    if ($commandMatch.Success) {
      $commandText = ConvertFrom-JsonStringLiteral $commandMatch.Groups[1].Value
    }
  }

  return [pscustomobject]@{
    Tool = $tool
    Cwd = Format-CodexWorkspacePath -Cwd $cwd
    Command = $commandText
  }
}
