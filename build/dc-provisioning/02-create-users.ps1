# Stop on the first failure. Without this the script runs to completion after
# a failed OU creation, leaves the domain half-provisioned, and still exits 0 --
# which is exactly how the "Users" OU collision below went unnoticed.
$ErrorActionPreference = "Stop"

# HTB submission requirement: PowerShell command history must be disabled
# unless the exploitation vector needs it (it doesn't here). This script
# types every plaintext credential as a literal argument, so it must not
# rely solely on the AllUsersAllHosts profile set in 00-prep-dc.ps1 -- a
# -NoProfile invocation (e.g. via vmrun) would skip that profile and still
# write this session's passwords to ConsoleHost_history.txt.
Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue

Import-Module ActiveDirectory

function New-OuIfMissing {
    param([string]$Name, [string]$Path)

    $dn = "OU=$Name,$Path"
    $existing = Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$dn)" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Output "OU already present: $dn"
    } else {
        New-ADOrganizationalUnit -Name $Name -Path $Path
        Write-Output "created OU: $dn"
    }
}

function Test-UserExists {
    param([string]$SamAccountName)
    return $null -ne (Get-ADUser -LDAPFilter "(sAMAccountName=$SamAccountName)" -ErrorAction SilentlyContinue)
}

New-OuIfMissing -Name "Service Accounts" -Path "DC=donerup,DC=htb"

# NOT "Users": the domain root already carries the built-in CN=Users container,
# so New-ADOrganizationalUnit -Name "Users" fails with 8305 (name already in
# use). The app searches the whole subtree from dc=donerup,dc=htb, so the OU
# name is cosmetic -- it just has to not collide.
New-OuIfMissing -Name "Employees" -Path "DC=donerup,DC=htb"

# Regular migrated user - carries the legacy plaintext-equivalent
# credential in `info`, matching the mock backend in Plan 1.
if (Test-UserExists "jdoe") {
    Write-Output "jdoe already present"
} else {
    New-ADUser -Name "jdoe" `
        -SamAccountName "jdoe" `
        -Path "OU=Employees,DC=donerup,DC=htb" `
        -AccountPassword (ConvertTo-SecureString "SogukDonerAyran7" -AsPlainText -Force) `
        -Enabled $true `
        -OtherAttributes @{ info = "SogukDonerAyran7" }
    Write-Output "created jdoe"
}

# LDAP bind service account - the "real path" credential from Plan 1 S5's
# CHANGELOG.md hint.
if (Test-UserExists "svc_ldap") {
    Write-Output "svc_ldap already present"
} else {
    New-ADUser -Name "svc_ldap" `
        -SamAccountName "svc_ldap" `
        -Path "OU=Service Accounts,DC=donerup,DC=htb" `
        -AccountPassword (ConvertTo-SecureString "KebapciBind2026!Sec" -AsPlainText -Force) `
        -Enabled $true `
        -PasswordNeverExpires $true
    Write-Output "created svc_ldap"
}

# Victim account for the GenericWrite edge (spec S7).
if (Test-UserExists "svc_backup") {
    Write-Output "svc_backup already present"
} else {
    New-ADUser -Name "svc_backup" `
        -SamAccountName "svc_backup" `
        -Path "OU=Service Accounts,DC=donerup,DC=htb" `
        -AccountPassword (ConvertTo-SecureString ([guid]::NewGuid().Guid) -AsPlainText -Force) `
        -Enabled $true
    Write-Output "created svc_backup"
}

# CRITICAL (spec S4.1): administrator must never receive an `info` value,
# not even an empty string - assert this explicitly rather than just
# skipping the assignment, so a future change to this script can't
# silently reintroduce it.
$adminInfo = (Get-ADUser -Identity administrator -Properties info).info
if ($null -ne $adminInfo) {
    throw "administrator has an 'info' value set - this breaks the LDAP injection path (spec S4.1)"
}
Write-Output "administrator.info confirmed absent"

# --- Content layer roster (spec 2026-08-29-donerup-content-layer-design.md) ---
# Inert texture only: every account below gets a GUID password (nobody can
# authenticate as it), no `info` attribute (the migration completed only for
# the pilot store, so jdoe stays the sole info holder), and no ACL edge.
# Two passes are required: an account cannot reference a manager that does
# not exist yet.

foreach ($ou in @("Store Operations", "Regional Management", "IT", "Finance")) {
    New-OuIfMissing -Name $ou -Path "OU=Employees,DC=donerup,DC=htb"
}
New-OuIfMissing -Name "Leavers" -Path "DC=donerup,DC=htb"

# No name here may contain the substring "Domain Admins" -- ldap_auth's
# is_privileged does a substring match, so such a group would bypass the
# LDAP injection entirely.
$contentGroups = @(
    "Store Managers",
    "Regional Managers",
    "IT Operations",
    "Finance Reporting",
    "Portal Report Authors",
    "Till Support (legacy)"
)
foreach ($g in $contentGroups) {
    # RFC 4515: parentheses in an assertion value must be escaped or the
    # filter is malformed. "Till Support (legacy)" would otherwise make this
    # guard fail silently under -ErrorAction SilentlyContinue, so every run
    # would try to create the group again and the second run would throw.
    $gFilterValue = $g -replace '\(', '\28' -replace '\)', '\29'
    if (Get-ADGroup -LDAPFilter "(cn=$gFilterValue)" -ErrorAction SilentlyContinue) {
        Write-Output "group already present: $g"
    } else {
        New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path "OU=Employees,DC=donerup,DC=htb"
        Write-Output "created group: $g"
    }
}

$rosterPath = Join-Path $PSScriptRoot "data\employees.csv"
$roster = Import-Csv $rosterPath

# Pass 1: accounts.
foreach ($row in $roster) {
    if (Test-UserExists $row.sam) {
        Write-Output "$($row.sam) already present"
        continue
    }
    $path = if ($row.ou -eq "Leavers") {
        "OU=Leavers,DC=donerup,DC=htb"
    } else {
        "OU=$($row.ou),OU=Employees,DC=donerup,DC=htb"
    }
    $attrs = @{
        title       = $row.title
        department  = $row.ou
        company     = "Donerup Restaurant Group"
        physicalDeliveryOfficeName = $row.office
        employeeID  = $row.employee_id
        description = $row.description
    }
    if ($row.mail) { $attrs["mail"] = $row.mail }

    New-ADUser -Name $row.display_name `
        -SamAccountName $row.sam `
        -DisplayName $row.display_name `
        -Path $path `
        -AccountPassword (ConvertTo-SecureString ([guid]::NewGuid().Guid) -AsPlainText -Force) `
        -Enabled ([bool]::Parse($row.enabled)) `
        -OtherAttributes $attrs
    Write-Output "created $($row.sam)"
}

# Pass 2: manager links and group membership, now that every referenced
# object exists.
foreach ($row in $roster) {
    if ($row.manager_sam) {
        $mgr = Get-ADUser -LDAPFilter "(sAMAccountName=$($row.manager_sam))"
        Set-ADUser -Identity $row.sam -Manager $mgr
    }
    foreach ($g in ($row.groups -split '\|' | Where-Object { $_ })) {
        $members = (Get-ADGroupMember -Identity $g -ErrorAction SilentlyContinue).SamAccountName
        if ($members -notcontains $row.sam) {
            Add-ADGroupMember -Identity $g -Members $row.sam
        }
    }
}
Write-Output "roster pass 2 complete: manager links and group membership"

# jdoe's canonical role, recorded on the account itself. Its info,
# password, OU and DN are deliberately untouched.
Set-ADUser -Identity jdoe -Description "Migration pilot test account, DNR-001. Retain until the password-reset rollout completes."
Write-Output "jdoe description set"
