param(
  [ValidateSet("approval", "clear", "session")]
  [string]$Action = "approval"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib" "paths.ps1")
. (Join-Path $PSScriptRoot "lib" "logging.ps1")
. (Join-Path $PSScriptRoot "lib" "context.ps1")
. (Join-Path $PSScriptRoot "lib" "state.ps1")
. (Join-Path $PSScriptRoot "lib" "overlay.ps1")
. (Join-Path $PSScriptRoot "lib" "actions.ps1")

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
