Import-Module ActiveDirectory

New-ADOrganizationalUnit -Name "Service Accounts" -Path "DC=donerup,DC=htb"
New-ADOrganizationalUnit -Name "Users" -Path "DC=donerup,DC=htb"

# Regular migrated user - carries the legacy plaintext-equivalent
# credential in `info`, matching the mock backend in Plan 1.
New-ADUser -Name "jdoe" `
    -SamAccountName "jdoe" `
    -Path "OU=Users,DC=donerup,DC=htb" `
    -AccountPassword (ConvertTo-SecureString "CorrectHorseBattery1" -AsPlainText -Force) `
    -Enabled $true `
    -OtherAttributes @{ info = "CorrectHorseBattery1" }

# LDAP bind service account - the "real path" credential from Plan 1 S5's
# CHANGELOG.md hint.
New-ADUser -Name "svc_ldap" `
    -SamAccountName "svc_ldap" `
    -Path "OU=Service Accounts,DC=donerup,DC=htb" `
    -AccountPassword (ConvertTo-SecureString "LdapBind2026!Str0ng" -AsPlainText -Force) `
    -Enabled $true `
    -PasswordNeverExpires $true

# Victim account for the GenericWrite edge (spec S7).
New-ADUser -Name "svc_backup" `
    -SamAccountName "svc_backup" `
    -Path "OU=Service Accounts,DC=donerup,DC=htb" `
    -AccountPassword (ConvertTo-SecureString ([guid]::NewGuid().Guid) -AsPlainText -Force) `
    -Enabled $true

# CRITICAL (spec S4.1): administrator must never receive an `info` value,
# not even an empty string - assert this explicitly rather than just
# skipping the assignment, so a future change to this script can't
# silently reintroduce it.
$adminInfo = (Get-ADUser -Identity administrator -Properties info).info
if ($null -ne $adminInfo) {
    throw "administrator has an 'info' value set - this breaks the LDAP injection path (spec S4.1)"
}
Write-Output "administrator.info confirmed absent"
