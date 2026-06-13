param(
  [ValidateSet("approval", "clear", "session")]
  [string]$Action = "approval"
)

$ErrorActionPreference = "Stop"

$libDir = Join-Path $PSScriptRoot "lib"

. (Join-Path $libDir "paths.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "context.ps1")
. (Join-Path $libDir "state.ps1")
. (Join-Path $libDir "overlay.ps1")
. (Join-Path $libDir "actions.ps1")

$inputJson = [Console]::In.ReadToEnd()
Write-DebugLog "action=$Action payload=$inputJson"
$context = Get-HookContext -InputJson $inputJson

switch ($Action) {
  "clear" {
    Clear-ApprovalOverlay -Context $context
    exit 0
  }
  "session" {
    Show-SessionOverlay -Context $context
    exit 0
  }
  default {
    Show-ApprovalOverlay -Context $context
    exit 0
  }
}
