# Stop on the first failure. Without this the script runs to completion after
# a failed OU creation, leaves the domain half-provisioned, and still exits 0 --
# which is exactly how the "Users" OU collision below went unnoticed.
$ErrorActionPreference = "Stop"

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
        -AccountPassword (ConvertTo-SecureString "CorrectHorseBattery1" -AsPlainText -Force) `
        -Enabled $true `
        -OtherAttributes @{ info = "CorrectHorseBattery1" }
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
        -AccountPassword (ConvertTo-SecureString "LdapBind2026!Str0ng" -AsPlainText -Force) `
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
