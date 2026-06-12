param(
  [string]$StateDir = (Join-Path $PSScriptRoot "approval-toast-active"),
  [string]$LogPath = (Join-Path $env:TEMP "codex-approval-toast-debug.log"),
  [string]$IconPath = "",
  [ValidateSet("approval", "session")]
  [string]$Kind = "approval"
)

$ErrorActionPreference = "Stop"
$idleExitAfter = if ($Kind -eq "session") { [TimeSpan]::FromSeconds(6) } else { [TimeSpan]::FromSeconds(30) }
$sessionVisibleFor = [TimeSpan]::FromSeconds(4)
$pollInterval = [TimeSpan]::FromMilliseconds(500)

function Write-OverlayLog {
  param([string]$Message)
  try {
    $timestamp = (Get-Date).ToString("o")
    "$timestamp overlay $Message" | Add-Content -Path $LogPath -Encoding UTF8
  } catch {}
}

function Get-StateDirMutexName {
  param([string]$Path)

  $bytes = [Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").Substring(0, 16)
    return "Global\CodexApprovalOverlay-$Kind-$hash"
  } finally {
    $sha.Dispose()
  }
}

function ConvertTo-DisplayCommand {
  param([string]$Command)

  if (-not $Command) {
    return "Codex approval requested"
  }

  $value = ($Command -replace '\s+', ' ').Trim()
  if ($value.Length -gt 150) {
    return $value.Substring(0, 147) + "..."
  }

  return $value
}

function Read-ApprovalStates {
  $states = @()

  try {
    if (-not (Test-Path $StateDir)) {
      return @()
    }

    Get-ChildItem -Path $StateDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
      ForEach-Object {
        try {
          $raw = Get-Content -Raw -Path $_.FullName -ErrorAction Stop
          $state = $raw | ConvertFrom-Json -ErrorAction Stop
          $timestamp = [DateTimeOffset]::MinValue
          if ($state.timestamp) {
            [DateTimeOffset]::TryParse([string]$state.timestamp, [ref]$timestamp) | Out-Null
          }
          if ($timestamp -eq [DateTimeOffset]::MinValue) {
            $timestamp = [DateTimeOffset]$_.LastWriteTime
          }

          $states += [pscustomobject]@{
            NotificationId = [string]$state.notification_id
            Timestamp = $timestamp
            Command = ConvertTo-DisplayCommand -Command ([string]$state.command)
            Cwd = [string]$state.cwd
            Tool = [string]$state.tool
          }
        } catch {
          Write-OverlayLog "state read failed path=$($_.FullName): $($_.Exception.Message)"
        }
      }
  } catch {
    Write-OverlayLog "state list failed: $($_.Exception.Message)"
  }

  return @($states | Sort-Object -Property Timestamp, NotificationId)
}

function New-TextBlock {
  param(
    [string]$Text,
    [double]$FontSize = 12,
    [string]$Foreground = "#FFE5E7EB",
    [string]$FontWeight = "Normal",
    [double]$Opacity = 1.0
  )

  $textBlock = New-Object Windows.Controls.TextBlock
  $textBlock.Text = $Text
  $textBlock.FontSize = $FontSize
  $textBlock.Foreground = $Foreground
  $textBlock.FontWeight = $FontWeight
  $textBlock.Opacity = $Opacity
  $textBlock.TextWrapping = "Wrap"
  return $textBlock
}

function New-StateCard {
  param(
    [object]$State,
    [int]$Index
  )

  $card = New-Object Windows.Controls.Border
  $card.Background = "#FF1F2937"
  $card.BorderBrush = "#FF374151"
  $card.BorderThickness = 1
  $card.CornerRadius = 6
  $card.Padding = "10,9,10,9"
  $card.Margin = "0,0,0,8"
  $card.Width = 390

  $stack = New-Object Windows.Controls.StackPanel
  $stack.Orientation = "Vertical"

  $heading = New-TextBlock -Text "$Index. $($State.Command)" -FontSize 13 -Foreground "#FFFFFFFF" -FontWeight "SemiBold"
  $heading.MaxHeight = 42
  $stack.Children.Add($heading) | Out-Null

  $meta = New-TextBlock -Text "$($State.Cwd) | $($State.Tool)" -FontSize 11 -Foreground "#FF9CA3AF" -Opacity 0.95
  $meta.Margin = "0,5,0,0"
  $meta.MaxHeight = 32
  $stack.Children.Add($meta) | Out-Null

  $card.Child = $stack
  return $card
}

$mutexName = Get-StateDirMutexName -Path $StateDir
$createdNew = $false
$mutex = New-Object Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
  Write-OverlayLog "already running stateDir=$StateDir"
  exit 0
}

try {
  Add-Type -AssemblyName PresentationCore
  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName WindowsBase

  $window = New-Object Windows.Window
  $window.Title = if ($Kind -eq "session") { "Codex" } else { "Codex approvals" }
  $window.WindowStyle = "None"
  $window.ResizeMode = "NoResize"
  $window.AllowsTransparency = $true
  $window.Background = "Transparent"
  $window.Topmost = $true
  $window.ShowInTaskbar = $false
  $window.ShowActivated = $false
  $window.SizeToContent = "WidthAndHeight"

  if ($IconPath -and (Test-Path $IconPath)) {
    try {
      $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$IconPath)
    } catch {
      Write-OverlayLog "icon load failed path=${IconPath}: $($_.Exception.Message)"
    }
  }

  $outer = New-Object Windows.Controls.Border
  $outer.Background = "#F2111827"
  $outer.BorderBrush = "#FF10A37F"
  $outer.BorderThickness = 1
  $outer.CornerRadius = 8
  $outer.Padding = "12"
  $outer.Effect = New-Object Windows.Media.Effects.DropShadowEffect -Property @{
    Color = [Windows.Media.Color]::FromRgb(0, 0, 0)
    Direction = 270
    ShadowDepth = 4
    Opacity = 0.35
    BlurRadius = 18
  }

  $root = New-Object Windows.Controls.StackPanel
  $root.Orientation = "Vertical"

  $header = New-TextBlock -Text "Codex approvals" -FontSize 13 -Foreground "#FFFFFFFF" -FontWeight "SemiBold"
  $header.Margin = "0,0,0,9"
  $root.Children.Add($header) | Out-Null

  $cardsPanel = New-Object Windows.Controls.StackPanel
  $cardsPanel.Orientation = "Vertical"

  $scrollViewer = New-Object Windows.Controls.ScrollViewer
  $scrollViewer.VerticalScrollBarVisibility = "Auto"
  $scrollViewer.HorizontalScrollBarVisibility = "Disabled"
  $scrollViewer.MaxHeight = 680
  $scrollViewer.Content = $cardsPanel
  $root.Children.Add($scrollViewer) | Out-Null

  $outer.Child = $root
  $window.Content = $outer

  $lastNonEmpty = Get-Date
  $lastStateKey = ""

  function Move-OverlayWindow {
    $workArea = [Windows.SystemParameters]::WorkArea
    $window.UpdateLayout()
    $window.Left = [Math]::Max($workArea.Left + 12, $workArea.Right - $window.ActualWidth - 18)
    $window.Top = [Math]::Max($workArea.Top + 12, $workArea.Bottom - $window.ActualHeight - 18)
  }

  function Refresh-Overlay {
    $states = @(Read-ApprovalStates)
    if ($Kind -eq "session" -and $states.Count -gt 0) {
      $now = [DateTimeOffset]::Now
      $states = @($states | Where-Object { ($now - $_.Timestamp) -lt $sessionVisibleFor })
      if ($states.Count -eq 0) {
        Get-ChildItem -Path $StateDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
          Remove-Item -Force -ErrorAction SilentlyContinue
      }
    }

    if ($states.Count -eq 0) {
      $window.Hide()
      if (((Get-Date) - $lastNonEmpty) -ge $idleExitAfter) {
        Write-OverlayLog "idle exit stateDir=$StateDir"
        $window.Close()
      }
      return
    }

    $script:lastNonEmpty = Get-Date
    $stateKey = ($states | ForEach-Object { $_.NotificationId }) -join "|"
    if ($stateKey -eq $script:lastStateKey -and $window.IsVisible) {
      Move-OverlayWindow
      return
    }
    $script:lastStateKey = $stateKey

    $cardsPanel.Children.Clear()
    $count = $states.Count
    $plural = if ($count -eq 1) { "" } else { "s" }
    if ($Kind -eq "session") {
      $header.Text = "Codex turn finished"
    } else {
      $header.Text = "$count Codex approval$plural pending"
    }

    for ($i = 0; $i -lt $states.Count; $i++) {
      $cardsPanel.Children.Add((New-StateCard -State $states[$i] -Index ($i + 1))) | Out-Null
    }

    if (-not $window.IsVisible) {
      $window.Show()
    }
    Move-OverlayWindow
  }

  $timer = New-Object Windows.Threading.DispatcherTimer
  $timer.Interval = $pollInterval
  $timer.Add_Tick({ Refresh-Overlay })
  $window.Add_Closed({
    try {
      $timer.Stop()
      $mutex.ReleaseMutex()
      $mutex.Dispose()
      [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvokeShutdown([Windows.Threading.DispatcherPriority]::Background)
    } catch {}
  })

  Refresh-Overlay
  $timer.Start()
  Write-OverlayLog "started kind=$Kind stateDir=$StateDir"
  [Windows.Threading.Dispatcher]::Run()
} catch {
  Write-OverlayLog "fatal: $($_.Exception.ToString())"
  try {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
  } catch {}
  exit 1
}
