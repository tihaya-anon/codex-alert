$script:NotificationPrefixApproval = "codex-approval"
$script:NotificationPrefixSessionEnd = "codex-session-end"
$script:LegacyApprovalNotificationId = "codex-approval"

$script:HooksRoot = Split-Path -Parent $PSScriptRoot
$script:DebugLogPath = Join-Path $env:TEMP "codex-approval-toast-debug.log"
$script:OverlayScriptPath = Join-Path $script:HooksRoot "approval-overlay.ps1"
$script:OverlayIconPath = Join-Path $script:HooksRoot "codex-approval-toast-icon.png"
$script:ApprovalStateDir = Join-Path $script:HooksRoot "approval-toast-active"
$script:SessionStateDir = Join-Path $script:HooksRoot "session-toast-active"
$script:LegacyApprovalStatePath = Join-Path $script:HooksRoot "approval-toast-active.json"
$script:ToastConfigPath = Join-Path $script:HooksRoot "approval-toast-config.json"
