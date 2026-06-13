param(
  [string]$StateDir = (Join-Path $PSScriptRoot "approval-toast-active"),
  [string]$LogPath = (Join-Path $env:TEMP "codex-approval-toast-debug.log"),
  [string]$IconPath = "",
  [ValidateSet("approval", "session")]
  [string]$Kind = "approval"
)

$ErrorActionPreference = "Stop"
$pollInterval = [TimeSpan]::FromMilliseconds(500)
$inactiveOpacity = 0.84
$activeOpacity = 1.0
$defaultCardWidth = 360
$sharedPositionStatePath = Join-Path $PSScriptRoot "overlay-window-state.json"
$legacyApprovalPositionStatePath = Join-Path $PSScriptRoot "overlay-window-state-approval.json"
$legacySessionPositionStatePath = Join-Path $PSScriptRoot "overlay-window-state-session.json"

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
            ItemKind = if ($state.item_kind) { [string]$state.item_kind } else { "approval" }
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

function Clear-StateDir {
  try {
    if (Test-Path $StateDir) {
      Get-ChildItem -Path $StateDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Write-OverlayLog "state dir cleared kind=$Kind stateDir=$StateDir"
  } catch {
    Write-OverlayLog "state dir clear failed kind=${Kind}: $($_.Exception.Message)"
  }
}

function Clear-SessionState {
  param([string]$NotificationId)

  try {
    if (-not $NotificationId) {
      return
    }

    $statePath = Join-Path $StateDir "$NotificationId.json"
    if (Test-Path $statePath) {
      Remove-Item -Path $statePath -Force -ErrorAction SilentlyContinue
      Write-OverlayLog "session state cleared path=$statePath"
    }
  } catch {
    Write-OverlayLog "session state clear failed kind=${Kind}: $($_.Exception.Message)"
  }
}

function New-CloseSessionButton {
  param([string]$NotificationId)

  $sessionButton = New-Object Windows.Controls.Button
  $sessionButton.Content = "Close"
  $sessionButton.HorizontalAlignment = "Right"
  $sessionButton.Margin = "0,8,0,0"
  $sessionButton.Padding = "10,4,10,4"
  $sessionButton.MinWidth = 72
  $sessionButton.Background = "#FF60A5FA"
  $sessionButton.Foreground = "#FFFFFFFF"
  $sessionButton.BorderBrush = "#FF60A5FA"
  $sessionButton.Cursor = [Windows.Input.Cursors]::Hand
  $sessionButton.Tag = [string]$NotificationId
  $sessionButton.Add_Click({
    param($sender, $eventArgs)
    $buttonNotificationId = [string]$sender.Tag
    if ($buttonNotificationId) {
      Clear-SessionState -NotificationId $buttonNotificationId
    }
    $window.Dispatcher.BeginInvoke(
      [Action]{ Refresh-Overlay },
      [Windows.Threading.DispatcherPriority]::Background
    ) | Out-Null
  })

  return $sessionButton
}

function Get-SavedWindowPosition {
  try {
    $candidatePaths = @(
      $sharedPositionStatePath,
      $legacyApprovalPositionStatePath,
      $legacySessionPositionStatePath
    )

    foreach ($path in $candidatePaths) {
      if (-not (Test-Path $path)) {
        continue
      }

      $position = Get-Content -Raw -Path $path | ConvertFrom-Json
      return [pscustomobject]@{
        Left = [double]$position.left
        Top = [double]$position.top
      }
    }

    return $null
  } catch {
    Write-OverlayLog "position load failed kind=${Kind}: $($_.Exception.Message)"
    return $null
  }
}

function Save-WindowPosition {
  param(
    [double]$Left,
    [double]$Top
  )

  try {
    @{
      left = $Left
      top = $Top
    } | ConvertTo-Json | Set-Content -Path $sharedPositionStatePath -Encoding UTF8
    Write-OverlayLog "position saved kind=$Kind left=$Left top=$Top"
  } catch {
    Write-OverlayLog "position save failed kind=${Kind}: $($_.Exception.Message)"
  }
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
  $card.Width = $defaultCardWidth

  $stack = New-Object Windows.Controls.StackPanel
  $stack.Orientation = "Vertical"

  if ($State.ItemKind -eq "session") {
    $card.BorderBrush = "#FF60A5FA"
    $pathText = New-TextBlock -Text $State.Cwd -FontSize 13 -Foreground "#FFE0F2FE" -FontWeight "SemiBold"
    $stack.Children.Add($pathText) | Out-Null
  } else {
    $heading = New-TextBlock -Text "Workspace awaiting review" -FontSize 12 -Foreground "#FFFFFFFF" -FontWeight "SemiBold"
    $stack.Children.Add($heading) | Out-Null

    if ($State.Cwd) {
      $pathText = New-TextBlock -Text $State.Cwd -FontSize 13 -Foreground "#FFE5E7EB" -FontWeight "SemiBold"
      $pathText.Margin = "0,7,0,0"
      $stack.Children.Add($pathText) | Out-Null
    }

    if ($State.Tool) {
      $meta = New-TextBlock -Text $State.Tool -FontSize 11 -Foreground "#FF9CA3AF" -Opacity 0.95
      $meta.Margin = "0,7,0,0"
      $stack.Children.Add($meta) | Out-Null
    }
  }

  $card.Child = $stack
  return $card
}

function Invoke-OverlaySound {
  param([int]$NewStateCount = 1)

  try {
    [System.Media.SystemSounds]::Exclamation.Play()
    Write-OverlayLog "sound played kind=$Kind newStates=$NewStateCount"
  } catch {
    Write-OverlayLog "sound failed kind=${Kind}: $($_.Exception.Message)"
  }
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
  $window.Title = "Codex"
  $window.WindowStyle = "None"
  $window.ResizeMode = "NoResize"
  $window.AllowsTransparency = $true
  $window.Background = "Transparent"
  $window.Topmost = $true
  $window.ShowInTaskbar = $false
  $window.ShowActivated = $false
  $window.WindowStartupLocation = "Manual"
  $window.SizeToContent = "WidthAndHeight"
  $window.Opacity = 0.0

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

  $headerHost = New-Object Windows.Controls.Border
  $headerHost.Background = "Transparent"
  $headerHost.Cursor = [Windows.Input.Cursors]::SizeAll
  $headerHost.Padding = "0,0,0,0"

  $headerStack = New-Object Windows.Controls.StackPanel
  $headerStack.Orientation = "Vertical"

  $header = New-TextBlock -Text "Codex" -FontSize 13 -Foreground "#FFFFFFFF" -FontWeight "SemiBold"
  $header.Margin = "0,0,0,9"
  $headerStack.Children.Add($header) | Out-Null

  $subheader = New-TextBlock -Text "" -FontSize 11 -Foreground "#FF9CA3AF" -Opacity 0.95
  $subheader.Margin = "0,0,0,10"
  $subheader.Visibility = "Collapsed"
  $headerStack.Children.Add($subheader) | Out-Null

  $headerHost.Child = $headerStack
  $root.Children.Add($headerHost) | Out-Null

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

  $lastStateKey = ""
  $seenStateIds = @{}
  $savedPosition = Get-SavedWindowPosition
  $script:PreferredLeft = if ($null -ne $savedPosition) { [double]$savedPosition.Left } else { [double]::NaN }
  $script:PreferredTop = if ($null -ne $savedPosition) { [double]$savedPosition.Top } else { [double]::NaN }

  function Set-InactiveWindowOpacity {
    if (-not $window.IsMouseOver) {
      $window.Opacity = $inactiveOpacity
    }
  }

  function Get-ClampedWindowPosition {
    param(
      [double]$Left,
      [double]$Top
    )

    $workArea = [Windows.SystemParameters]::WorkArea
    $window.UpdateLayout()
    $maxLeft = [Math]::Max($workArea.Left + 12, $workArea.Right - $window.ActualWidth - 12)
    $maxTop = [Math]::Max($workArea.Top + 12, $workArea.Bottom - $window.ActualHeight - 12)

    return [pscustomobject]@{
      Left = [Math]::Min([Math]::Max($Left, $workArea.Left + 12), $maxLeft)
      Top = [Math]::Min([Math]::Max($Top, $workArea.Top + 12), $maxTop)
    }
  }

  function Get-DefaultWindowPosition {
    param(
      [double]$WindowWidth,
      [double]$WindowHeight
    )

    $workArea = [Windows.SystemParameters]::WorkArea
    return [pscustomobject]@{
      Left = [Math]::Max($workArea.Left + 12, $workArea.Right - $WindowWidth - 18)
      Top = [Math]::Max($workArea.Top + 12, $workArea.Bottom - $WindowHeight - 18)
    }
  }

  function Measure-OverlayWindow {
    $availableSize = New-Object Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)
    $window.Measure($availableSize)
    $window.Arrange((New-Object Windows.Rect(0, 0, $window.DesiredSize.Width, $window.DesiredSize.Height)))
    $window.UpdateLayout()
  }

  function Move-OverlayWindow {
    if (-not [double]::IsNaN($script:PreferredLeft) -and -not [double]::IsNaN($script:PreferredTop)) {
      $position = Get-ClampedWindowPosition -Left $script:PreferredLeft -Top $script:PreferredTop
      $window.Left = $position.Left
      $window.Top = $position.Top
      return
    }

    $position = Get-DefaultWindowPosition -WindowWidth $window.ActualWidth -WindowHeight $window.ActualHeight
    $window.Left = $position.Left
    $window.Top = $position.Top
  }

  function Save-CurrentWindowPosition {
    $position = Get-ClampedWindowPosition -Left $window.Left -Top $window.Top
    $script:PreferredLeft = $position.Left
    $script:PreferredTop = $position.Top
    Save-WindowPosition -Left $position.Left -Top $position.Top
  }

  function Refresh-Overlay {
    $states = @(Read-ApprovalStates)
    if ($states.Count -eq 0) {
      $window.Hide()
      Write-OverlayLog "no states remaining kind=$Kind"
      $window.Close()
      return
    }

    $stateKey = ($states | ForEach-Object { $_.NotificationId }) -join "|"
    $newStateCount = 0
    foreach ($state in $states) {
      $notificationId = [string]$state.NotificationId
      if ($notificationId -and -not $script:seenStateIds.ContainsKey($notificationId)) {
        $script:seenStateIds[$notificationId] = $true
        $newStateCount += 1
      }
    }

    if ($newStateCount -gt 0) {
      Invoke-OverlaySound -NewStateCount $newStateCount
    }

    if ($stateKey -eq $script:lastStateKey -and $window.IsVisible) {
      Move-OverlayWindow
      return
    }
    $script:lastStateKey = $stateKey

    $cardsPanel.Children.Clear()
    $count = $states.Count
    $plural = if ($count -eq 1) { "" } else { "s" }
    $sessionStates = @($states | Where-Object { [string]$_.ItemKind -eq "session" })
    $approvalStates = @($states | Where-Object { [string]$_.ItemKind -ne "session" })
    $outer.BorderBrush = if ($approvalStates.Count -gt 0) { "#FF10A37F" } else { "#FF60A5FA" }

    if ($approvalStates.Count -gt 0) {
      $approvalPlural = if ($approvalStates.Count -eq 1) { "" } else { "s" }
      $header.Text = "$($approvalStates.Count) approval$approvalPlural pending"
      $uniqueCwds = @($approvalStates | ForEach-Object { $_.Cwd } | Where-Object { $_ } | Select-Object -Unique)
      if ($uniqueCwds.Count -eq 1) {
        $subheader.Text = $uniqueCwds[0]
      } elseif ($uniqueCwds.Count -gt 1) {
        $subheader.Text = "$($uniqueCwds.Count) workspaces waiting for review"
      } else {
        $subheader.Text = "Return to Codex to allow or reject"
      }
      $subheader.Visibility = "Visible"
    } else {
      $header.Text = "Codex"
      if ($sessionStates.Count -gt 0 -and $sessionStates[0].Cwd) {
        $subheader.Text = $sessionStates[0].Cwd
      } else {
        $subheader.Text = "Turn finished"
      }
      $subheader.Visibility = "Visible"
    }

    for ($i = 0; $i -lt $sessionStates.Count; $i++) {
      $sessionState = $sessionStates[$i]
      $sessionCard = New-StateCard -State $sessionState -Index ($i + 1)

      $sessionCardStack = [Windows.Controls.StackPanel]$sessionCard.Child
      $sessionButton = New-CloseSessionButton -NotificationId $sessionState.NotificationId
      $sessionCardStack.Children.Add($sessionButton) | Out-Null
      $cardsPanel.Children.Add($sessionCard) | Out-Null
    }

    if ($approvalStates.Count -gt 0) {
      $workspaceGroups = @($approvalStates | Group-Object -Property Cwd)
      for ($i = 0; $i -lt $workspaceGroups.Count; $i++) {
        $group = $workspaceGroups[$i]
        $toolGroups = @($group.Group | Group-Object -Property Tool)
        $toolSummary = if ($group.Count -eq 1) {
          "1 approval pending"
        } elseif ($toolGroups.Count -eq 0) {
          "$($group.Count) approvals pending"
        } else {
          "$($group.Count) approvals pending"
        }
        $groupState = [pscustomobject]@{
          ItemKind = "approval"
          Tool = $toolSummary
          Cwd = if ($group.Name) { [string]$group.Name } else { "Unknown workspace" }
        }
        $cardsPanel.Children.Add((New-StateCard -State $groupState -Index ($sessionStates.Count + $i + 1))) | Out-Null
      }
    }

    if (-not $window.IsVisible) {
      Measure-OverlayWindow
      Move-OverlayWindow
      $window.Show()
      $window.Opacity = $inactiveOpacity
    } else {
      Move-OverlayWindow
    }
    Set-InactiveWindowOpacity
  }

  $timer = New-Object Windows.Threading.DispatcherTimer
  $timer.Interval = $pollInterval
  $timer.Add_Tick({ Refresh-Overlay })
  $window.Add_MouseEnter({
    $window.Opacity = $activeOpacity
  })
  $window.Add_MouseLeave({
    Set-InactiveWindowOpacity
  })
  $headerHost.Add_MouseLeftButtonDown({
    try {
      $window.Opacity = $activeOpacity
      $window.DragMove()
      Save-CurrentWindowPosition
      Set-InactiveWindowOpacity
    } catch {
      Write-OverlayLog "drag failed kind=${Kind}: $($_.Exception.Message)"
    }
  })
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
