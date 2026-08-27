<#
.SYNOPSIS
  Donerup DC prep - run on the fresh Windows Server 2022 VM, elevated.

.DESCRIPTION
  Does everything that must happen BEFORE 01-promote-dc.ps1:
    SKU sanity check -> static IP -> DNS -> Private profile -> ICMP rule
    -> red-state domain check -> rename to DC01 and reboot.
  Addresses match build/network/config.env (DC_IP / AD_VLAN_HOST_IP).

.PARAMETER LabMac
  MAC of the NIC on the AD VLAN (VMnet3 / adlab0), as recorded in the VM's
  .vmx. Only needed when the VM has more than one connected adapter; with a
  single adapter the script picks it automatically.

.PARAMETER StrayMac
  MAC of an adapter that must be disabled before promotion. A domain
  controller with a second NIC on an unrelated network registers itself in DNS
  on both and breaks the AD VLAN isolation the box depends on.
#>
param(
    [string]$LabMac   = '',
    [string]$StrayMac = ''
)

$ErrorActionPreference = 'Stop'

$DcIp       = '10.10.20.10'
$Prefix     = 24
$Gateway    = '10.10.20.1'
$NewName    = 'DC01'

function Say($msg) { Write-Host "[prep] $msg" -ForegroundColor Cyan }
function Bad($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }

# --- 0. SKU sanity check ------------------------------------------------
$caption = (Get-CimInstance Win32_OperatingSystem).Caption
Say "OS: $caption"
if (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) {
    Bad "Get-WindowsFeature is missing - this is a CLIENT SKU, not Windows Server."
    Bad "AD DS can never be installed here. Stop and reinstall with Server 2022."
    exit 1
}
$feat = Get-WindowsFeature AD-Domain-Services
Say "AD-Domain-Services feature state: $($feat.InstallState)"

# --- 1. Pick the adapter ------------------------------------------------
# Adapter names and ifIndexes are not stable across reboots, and a VM built
# with more than one NIC makes "the one that is Up" return an array - which
# fails later with "Cannot convert value to type System.String" on
# -InterfaceAlias. Select by MAC when the caller supplies one.
if ($StrayMac) {
    $stray = Get-NetAdapter | Where-Object { $_.MacAddress -eq $StrayMac }
    if ($stray -and $stray.Status -ne 'Disabled') {
        Say "Disabling stray adapter '$($stray.Name)' ($StrayMac)"
        Disable-NetAdapter -Name $stray.Name -Confirm:$false
    } elseif ($stray) {
        Say "Stray adapter $StrayMac already disabled"
    } else {
        Say "No adapter with MAC $StrayMac present - nothing to disable"
    }
}

if ($LabMac) {
    $lab = Get-NetAdapter | Where-Object { $_.MacAddress -eq $LabMac }
    if (-not $lab) {
        Bad "No adapter with MAC $LabMac found. Adapters present:"
        Get-NetAdapter | Format-Table Name, Status, MacAddress -AutoSize | Out-String | Write-Host
        exit 1
    }
    if ($lab.Status -eq 'Disabled') {
        Say "Enabling lab adapter '$($lab.Name)'"
        Enable-NetAdapter -Name $lab.Name -Confirm:$false
        Start-Sleep -Seconds 3
        $lab = Get-NetAdapter | Where-Object { $_.MacAddress -eq $LabMac }
    }
} else {
    $candidates = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual })
    if ($candidates.Count -ne 1) {
        Bad "Expected exactly 1 connected physical adapter, found $($candidates.Count):"
        Get-NetAdapter | Format-Table Name, Status, MacAddress -AutoSize | Out-String | Write-Host
        Bad "Re-run with -LabMac (and -StrayMac for the one to disable); the MACs are in the VM's .vmx."
        exit 1
    }
    $lab = $candidates[0]
}
$if = $lab.Name
Say "Using adapter: $if ($($lab.MacAddress), status $($lab.Status))"

# --- 2. Static IP -------------------------------------------------------
Say "Clearing DHCP config and setting $DcIp/$Prefix gw $Gateway"
Set-NetIPInterface -InterfaceAlias $if -Dhcp Disabled
Remove-NetIPAddress -InterfaceAlias $if -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute     -InterfaceAlias $if -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceAlias $if -IPAddress $DcIp -PrefixLength $Prefix -DefaultGateway $Gateway | Out-Null
# DNS points at itself; the DNS role gets installed during promotion.
Set-DnsClientServerAddress -InterfaceAlias $if -ServerAddresses 127.0.0.1

# --- 3. Private profile + ICMP -----------------------------------------
# The profile can take a moment to re-evaluate after the address change.
$profileSet = $false
foreach ($try in 1..10) {
    try {
        Set-NetConnectionProfile -InterfaceAlias $if -NetworkCategory Private -ErrorAction Stop
        $profileSet = $true
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}
if ($profileSet) { Say "Network profile set to Private" }
else { Bad "Could not set the profile to Private - do it by hand before promoting." }

if (-not (Get-NetFirewallRule -DisplayName 'Allow ICMPv4-In' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Allow ICMPv4-In' -Protocol ICMPv4 -IcmpType 8 `
        -Direction Inbound -Action Allow | Out-Null
    Say "Added inbound ICMPv4 echo rule"
} else {
    Say "ICMPv4 echo rule already present"
}

# --- 4. Report ----------------------------------------------------------
Say "Current IPv4 config:"
Get-NetIPAddress -InterfaceAlias $if -AddressFamily IPv4 |
    Format-Table IPAddress, PrefixLength -AutoSize | Out-String | Write-Host
Get-NetConnectionProfile -InterfaceAlias $if |
    Format-Table Name, NetworkCategory -AutoSize | Out-String | Write-Host

Say "Pinging the Kali gateway $Gateway (fails harmlessly if Kali is powered off):"
if (Test-Connection -ComputerName $Gateway -Count 2 -Quiet) { Say "gateway reachable" }
else { Say "gateway NOT reachable - check the VM is on VMnet3 and Kali is up" }

# --- 5. Red-state check (plan Task 1, step 2) ---------------------------
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$domain = Get-ADDomain -ErrorAction SilentlyContinue
if ($domain -and $domain.DNSRoot -eq 'donerup.htb') {
    Say "PASS: domain donerup.htb is already up - skip 01-promote-dc.ps1"
} else {
    Say "FAIL: donerup.htb domain not found  <-- expected red state, good"
}

# --- 6. Rename and reboot ----------------------------------------------
if ($env:COMPUTERNAME -eq $NewName) {
    Say "Already named $NewName - no reboot needed. Run 01-promote-dc.ps1 next."
} else {
    Say "Renaming $env:COMPUTERNAME -> $NewName and rebooting in 10 seconds."
    Say "After the reboot, run 01-promote-dc.ps1 from this same drive."
    Start-Sleep -Seconds 10
    Rename-Computer -NewName $NewName -Restart -Force
}
