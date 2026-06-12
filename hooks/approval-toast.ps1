param(
  [switch]$Clear,
  [switch]$SessionEnd
)

$approvalNotificationPrefix = "codex-approval"
$sessionEndNotificationPrefix = "codex-session-end"
$legacyApprovalNotificationId = "codex-approval"
$legacySessionEndNotificationId = "codex-session-end"
$debugPath = Join-Path $env:TEMP "codex-approval-toast-debug.log"
$appId = "OpenAI.Codex.ApprovalToast"
$appName = "Codex"
$appRegistryPath = "HKCU:\Software\Classes\AppUserModelId\$appId"
$appIconPath = Join-Path $env:LOCALAPPDATA "CodexApprovalToast\Icon.png"
$bundledIconPath = Join-Path $PSScriptRoot "codex-approval-toast-icon.png"
$stateDir = Join-Path $PSScriptRoot "approval-toast-active"
$legacyStatePath = Join-Path $PSScriptRoot "approval-toast-active.json"
$configPath = Join-Path $PSScriptRoot "approval-toast-config.json"
$shortcutPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Codex.lnk"

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

function Set-ToastAppIdentity {
  try {
    if (-not ([System.Management.Automation.PSTypeName]"CodexToastAppIdentityV2").Type) {
      Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class CodexToastAppIdentityV2 {
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
  public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
  public static extern int GetCurrentProcessExplicitAppUserModelID(out IntPtr appId);

  [DllImport("ole32.dll", PreserveSig = true)]
  public static extern void CoTaskMemFree(IntPtr ptr);
}
"@ -ErrorAction Stop
    }

    $setHr = [CodexToastAppIdentityV2]::SetCurrentProcessExplicitAppUserModelID($appId)
    $currentPtr = [IntPtr]::Zero
    $getHr = [CodexToastAppIdentityV2]::GetCurrentProcessExplicitAppUserModelID([ref]$currentPtr)
    $currentAppId = ""
    if ($currentPtr -ne [IntPtr]::Zero) {
      $currentAppId = [Runtime.InteropServices.Marshal]::PtrToStringUni($currentPtr)
      [CodexToastAppIdentityV2]::CoTaskMemFree($currentPtr)
    }

    Write-DebugLog "app identity setHr=$setHr getHr=$getHr requested=$appId current=$currentAppId"
  } catch {
    Write-DebugLog "appid failed: $($_.Exception.Message)"
  }
}

function Write-EnvironmentDiagnostics {
  try {
    $process = Get-Process -Id $PID -ErrorAction SilentlyContinue
    Write-DebugLog "env pid=$PID process=$($process.ProcessName) path=$($process.Path) ps=$PSHOME shortcutPath=$shortcutPath"
  } catch {
    Write-DebugLog "env diag failed: $($_.Exception.Message)"
  }
}

function Write-ShortcutDiagnostics {
  try {
    if (-not (Test-Path $shortcutPath)) {
      Write-DebugLog "shortcut missing path=$shortcutPath"
      return
    }

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)

    $folderPath = Split-Path -Parent $shortcutPath
    $fileName = Split-Path -Leaf $shortcutPath
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($folderPath)
    $item = $folder.ParseName($fileName)
    $shortcutAppId = $item.ExtendedProperty("System.AppUserModel.ID")
    $relaunchCommand = $item.ExtendedProperty("System.AppUserModel.RelaunchCommand")
    $relaunchName = $item.ExtendedProperty("System.AppUserModel.RelaunchDisplayNameResource")
    $relaunchIcon = $item.ExtendedProperty("System.AppUserModel.RelaunchIconResource")

    Write-DebugLog "shortcut exists target=$($shortcut.TargetPath) args=$($shortcut.Arguments) icon=$($shortcut.IconLocation) appid=$shortcutAppId relaunchCommand=$relaunchCommand relaunchName=$relaunchName relaunchIcon=$relaunchIcon"
  } catch {
    Write-DebugLog "shortcut diag failed: $($_.Exception.Message)"
  }
}

function Ensure-ToastIcon {
  try {
    $iconDir = Split-Path -Parent $appIconPath
    New-Item -ItemType Directory -Path $iconDir -Force | Out-Null

    if (Test-Path $bundledIconPath) {
      Copy-Item -Path $bundledIconPath -Destination $appIconPath -Force
      Write-DebugLog "icon copied source=$bundledIconPath path=$appIconPath"
      return
    }

    if (Test-Path $appIconPath) {
      Write-DebugLog "icon source missing, keeping existing path=$appIconPath"
    } else {
      Write-DebugLog "icon source missing path=$bundledIconPath"
    }
  } catch {
    Write-DebugLog "icon create failed: $($_.Exception.Message)"
  }
}

function Ensure-ToastAppRegistration {
  try {
    New-Item -Path $appRegistryPath -Force | Out-Null
    Ensure-ToastIcon

    New-ItemProperty -Path $appRegistryPath -Name DisplayName -Value $appName -PropertyType String -Force | Out-Null
    if (Test-Path $appIconPath) {
      New-ItemProperty -Path $appRegistryPath -Name IconUri -Value $appIconPath -PropertyType String -Force | Out-Null
      New-ItemProperty -Path $appRegistryPath -Name IconBackgroundColor -Value "FF111827" -PropertyType String -Force | Out-Null
    }

    Write-DebugLog "app registration ensured path=$appRegistryPath displayName=$appName icon=$appIconPath"
  } catch {
    Write-DebugLog "app registration failed: $($_.Exception.Message)"
  }
}

function Write-AppRegistrationDiagnostics {
  try {
    $props = Get-ItemProperty -Path $appRegistryPath -ErrorAction Stop
    Write-DebugLog "app registration displayName=$($props.DisplayName) iconUri=$($props.IconUri) iconBackground=$($props.IconBackgroundColor) customActivator=$($props.CustomActivator)"
  } catch {
    Write-DebugLog "app registration diag failed: $($_.Exception.Message)"
  }
}

function Get-ShortcutAppId {
  try {
    if (-not (Test-Path $shortcutPath)) {
      return ""
    }

    $folderPath = Split-Path -Parent $shortcutPath
    $fileName = Split-Path -Leaf $shortcutPath
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($folderPath)
    $item = $folder.ParseName($fileName)
    return [string]$item.ExtendedProperty("System.AppUserModel.ID")
  } catch {
    Write-DebugLog "shortcut appid read failed: $($_.Exception.Message)"
    return ""
  }
}

function Install-ToastShortcut {
  try {
    if (-not ([System.Management.Automation.PSTypeName]"CodexToastShortcutInstallerV1").Type) {
      Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

[ComImport]
[Guid("00021401-0000-0000-C000-000000000046")]
public class ShellLink {}

[ComImport]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[Guid("000214F9-0000-0000-C000-000000000046")]
public interface IShellLinkW {
  void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, IntPtr pfd, uint fFlags);
  void GetIDList(out IntPtr ppidl);
  void SetIDList(IntPtr pidl);
  void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
  void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
  void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
  void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
  void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
  void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
  void GetHotkey(out short pwHotkey);
  void SetHotkey(short wHotkey);
  void GetShowCmd(out int piShowCmd);
  void SetShowCmd(int iShowCmd);
  void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
  void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
  void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
  void Resolve(IntPtr hwnd, uint fFlags);
  void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
}

[ComImport]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[Guid("00000138-0000-0000-C000-000000000046")]
public interface IPropertyStore {
  void GetCount(out uint cProps);
  void GetAt(uint iProp, out PropertyKey pkey);
  void GetValue(ref PropertyKey key, out PropVariant pv);
  void SetValue(ref PropertyKey key, ref PropVariant pv);
  void Commit();
}

[StructLayout(LayoutKind.Sequential, Pack = 4)]
public struct PropertyKey {
  public Guid fmtid;
  public uint pid;

  public PropertyKey(Guid fmtid, uint pid) {
    this.fmtid = fmtid;
    this.pid = pid;
  }
}

[StructLayout(LayoutKind.Sequential)]
public struct PropVariant {
  public ushort vt;
  public ushort wReserved1;
  public ushort wReserved2;
  public ushort wReserved3;
  public IntPtr p;

  public static PropVariant FromString(string value) {
    PropVariant variant = new PropVariant();
    variant.vt = 31;
    variant.p = Marshal.StringToCoTaskMemUni(value);
    return variant;
  }
}

public static class CodexToastShortcutInstallerV1 {
  [DllImport("ole32.dll", PreserveSig = true)]
  private static extern int PropVariantClear(ref PropVariant pvar);

  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
  private static extern int SHGetPropertyStoreFromParsingName(
    [MarshalAs(UnmanagedType.LPWStr)] string path,
    IntPtr bindContext,
    uint flags,
    ref Guid riid,
    out IntPtr propertyStore);

  public static void Install(string shortcutPath, string targetPath, string arguments, string iconPath, int iconIndex, string appId) {
    object shellLinkObject = new ShellLink();
    string step = "start";
    try {
      step = "create shell link";
      IShellLinkW shellLink = (IShellLinkW)shellLinkObject;
      shellLink.SetPath(targetPath);
      shellLink.SetArguments(arguments ?? "");
      shellLink.SetDescription("Codex");
      shellLink.SetIconLocation(iconPath, iconIndex);

      step = "save shortcut";
      IPersistFile file = (IPersistFile)shellLinkObject;
      file.Save(shortcutPath, true);

      step = "open property store";
      Guid propertyStoreGuid = new Guid("00000138-0000-0000-C000-000000000046");
      IntPtr propertyStorePtr = IntPtr.Zero;
      int hr = SHGetPropertyStoreFromParsingName(shortcutPath, IntPtr.Zero, 2, ref propertyStoreGuid, out propertyStorePtr);
      if (hr != 0) {
        Marshal.ThrowExceptionForHR(hr);
      }

      step = "marshal property store";
      IPropertyStore propertyStore = (IPropertyStore)Marshal.GetObjectForIUnknown(propertyStorePtr);
      PropertyKey appIdKey = new PropertyKey(
        new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
        5);
      PropVariant appIdValue = PropVariant.FromString(appId);
      try {
        step = "set appid";
        propertyStore.SetValue(ref appIdKey, ref appIdValue);
        step = "commit appid";
        propertyStore.Commit();
      } finally {
        PropVariantClear(ref appIdValue);
        if (propertyStore != null) {
          Marshal.FinalReleaseComObject(propertyStore);
        }
        if (propertyStorePtr != IntPtr.Zero) {
          Marshal.Release(propertyStorePtr);
        }
      }
    } catch (Exception ex) {
      throw new InvalidOperationException("shortcut install step=" + step + " failed: " + ex.Message, ex);
    } finally {
      if (shellLinkObject != null) {
        Marshal.FinalReleaseComObject(shellLinkObject);
      }
    }
  }
}
"@ -ErrorAction Stop
    }

    $shortcutDir = Split-Path -Parent $shortcutPath
    New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null

    $targetPath = Join-Path $PSHOME "powershell.exe"
    $arguments = "-NoProfile"
    $iconPath = Join-Path $env:SystemRoot "System32\shell32.dll"
    [CodexToastShortcutInstallerV1]::Install($shortcutPath, $targetPath, $arguments, $iconPath, 44, $appId)
    Write-DebugLog "shortcut installed path=$shortcutPath target=$targetPath appid=$appId icon=$iconPath,44"
  } catch {
    Write-DebugLog "shortcut install failed: $($_.Exception.ToString())"
  }
}

function Ensure-ToastShortcut {
  $currentShortcutAppId = Get-ShortcutAppId
  if ($currentShortcutAppId -ne $appId) {
    Write-DebugLog "shortcut appid mismatch expected=$appId actual=$currentShortcutAppId"
    Install-ToastShortcut
  }
}

function ConvertTo-ToastXmlText {
  param([string]$Value)
  return [System.Security.SecurityElement]::Escape($Value)
}

function New-ApprovalToastXml {
  param([string[]]$Text)

  $textXml = ($Text | ForEach-Object {
    "      <text>$((ConvertTo-ToastXmlText $_))</text>"
  }) -join "`n"

  return @"
<toast duration="long" scenario="reminder">
  <visual>
    <binding template="ToastGeneric">
$textXml
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Reminder" />
</toast>
"@
}

function Normalize-ApprovalCommand {
  param([string]$Command)
  if (-not $Command) {
    return ""
  }

  return ($Command -replace '\s+', ' ').Trim()
}

function New-ToastNotificationId {
  param([string]$Prefix)

  $timestamp = (Get-Date).ToString("yyyyMMddHHmmssfff")
  $nonce = [Guid]::NewGuid().ToString("N").Substring(0, 8)
  return "$Prefix-$timestamp-$nonce"
}

function Get-ApprovalStatePath {
  param([string]$NotificationId)
  return (Join-Path $stateDir "$NotificationId.json")
}

function Submit-ApprovalToast {
  param(
    [string[]]$Text,
    [string]$NotificationId
  )

  try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $toastXml = New-ApprovalToastXml -Text $Text
    Write-DebugLog "direct submit attempt appid=$appId xml=$($toastXml -replace '\s+', ' ')"

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)

    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $toast.Tag = $NotificationId
    $toast.Group = $NotificationId

    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)
    $notifier.Show($toast)
    Write-DebugLog "direct submit appid=$appId id=$NotificationId"
    return $true
  } catch {
    Write-DebugLog "direct submit failed: $($_.Exception.Message)"
    return $false
  }
}

function Clear-ApprovalToast {
  param([string[]]$NotificationIds)

  if (-not $NotificationIds -or $NotificationIds.Count -eq 0) {
    return
  }

  try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    foreach ($notificationId in $NotificationIds) {
      [Windows.UI.Notifications.ToastNotificationManager]::History.Remove($notificationId, $notificationId, $appId)
    }
    Write-DebugLog "direct clear appid=$appId ids=$($NotificationIds -join ',')"
  } catch {
    Write-DebugLog "direct clear failed: $($_.Exception.Message)"
  }

  try {
    Import-Module BurntToast -ErrorAction SilentlyContinue
    foreach ($notificationId in $NotificationIds) {
      Remove-BTNotification -UniqueIdentifier $notificationId -ErrorAction SilentlyContinue
      try {
        Remove-BTNotification -Tag $notificationId -Group $notificationId -ErrorAction SilentlyContinue
      } catch {}
    }
  } catch {
    Write-DebugLog "clear failed: $($_.Exception.Message)"
  }
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
  Set-ToastAppIdentity
  Write-DebugLog "clear requested tool=$($context.Tool) cwd=$($context.Cwd) command=$(Normalize-ApprovalCommand -Command $context.Command)"

  $states = @(Get-ApprovalStates)
  $statesToClear = @(Select-ApprovalStatesForClear `
    -States $states `
    -Tool $context.Tool `
    -Cwd $context.Cwd `
    -Command $context.Command)
  $notificationIds = @($statesToClear | ForEach-Object { [string]$_.notification_id } | Where-Object { $_ })

  Clear-ApprovalToast -NotificationIds $notificationIds
  Remove-ApprovalStates -States $statesToClear
  exit 0
}

Set-ToastAppIdentity

Write-EnvironmentDiagnostics
Ensure-ToastAppRegistration
Write-AppRegistrationDiagnostics
Write-ShortcutDiagnostics

$inputJson = [Console]::In.ReadToEnd()
Write-DebugLog "payload=$inputJson"

$context = Get-HookContext -InputJson $inputJson
$tool = $context.Tool
$cwd = $context.Cwd
$cmd = $context.Command

if ($SessionEnd) {
  $notificationId = New-ToastNotificationId -Prefix $sessionEndNotificationPrefix
  $toastText = @($cwd)
  Write-DebugLog "session end toast id=$notificationId text=$($toastText -join ' || ')"
  Submit-ApprovalToast -Text $toastText -NotificationId $notificationId | Out-Null
  exit 0
}

$notificationId = New-ToastNotificationId -Prefix $approvalNotificationPrefix
$displayCmd = Normalize-ApprovalCommand -Command $cmd
if ($displayCmd.Length -gt 120) {
  $displayCmd = $displayCmd.Substring(0, 117) + "..."
}

$title = if ($displayCmd) { $displayCmd } else { "Codex approval requested" }
$contextText = "$cwd | $tool"

$toastText = @(
  $title,
  $contextText
)

Write-DebugLog "toast id=$notificationId text=$($toastText -join ' || ')"
Write-ApprovalState -NotificationId $notificationId -Tool $tool -Cwd $cwd -Command $cmd

if (Submit-ApprovalToast -Text $toastText -NotificationId $notificationId) {
  exit 0
}

try {
  $textItems = $toastText | ForEach-Object { New-BTText -Text $_ -Wrap }
  $binding = New-BTBinding -Children $textItems
  $visual = New-BTVisual -BindingGeneric $binding
  $audio = New-BTAudio -Source "ms-winsoundevent:Notification.Reminder"
  $content = New-BTContent `
    -Visual $visual `
    -Audio $audio `
    -Scenario Reminder `
    -Duration Long

  Submit-BTNotification `
    -Content $content `
    -UniqueIdentifier $notificationId
} catch {
  Write-DebugLog "submit fallback: $($_.Exception.Message)"
  try {
    New-BurntToastNotification `
      -Text $toastText `
      -Sound Reminder `
      -UniqueIdentifier $notificationId
  } catch {
    Write-DebugLog "submit failed: $($_.Exception.Message)"
  }
}
