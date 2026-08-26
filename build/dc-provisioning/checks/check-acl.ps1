# SID-based ACL check (locale-independent), mirroring check-root-flag.ps1:
# dsacls's rights/trustee text is not guaranteed English on non-English
# Windows, so resolve svc_ldap to its SID and inspect the AD object's ACL
# directly instead of matching dsacls's printed output.
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$svcLdap = Get-ADUser -Identity svc_ldap -ErrorAction SilentlyContinue
if (-not $svcLdap) {
    Write-Output "FAIL: could not resolve svc_ldap via Get-ADUser - cannot check its ACL grant"
    exit 1
}
$svcLdapSid = $svcLdap.SID.Value

$acl = Get-Acl -Path "AD:CN=svc_backup,OU=Service Accounts,DC=donerup,DC=htb" -ErrorAction SilentlyContinue
if (-not $acl) {
    Write-Output "FAIL: could not read svc_backup's ACL via Get-Acl - cannot check its GenericWrite grant"
    exit 1
}

# GenericWrite is a composite right (ReadControl | WriteProperty | Self), not
# a single bit. A plain -band test is an ANY match and would false-PASS on an
# ACE that only grants WriteProperty. Require every GenericWrite bit present
# so a narrower grant fails and a broader one (e.g. GenericAll) still passes.
$gw = [System.DirectoryServices.ActiveDirectoryRights]::GenericWrite
$hasGenericWrite = $false
foreach ($ace in $acl.Access) {
    $sidValue = $null
    try {
        $sidValue = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch {
        Write-Output "WARN: skipping ACE with untranslatable identity '$($ace.IdentityReference)'"
        continue
    }
    if ($sidValue -eq $svcLdapSid -and (($ace.ActiveDirectoryRights -band $gw) -eq $gw)) {
        $hasGenericWrite = $true
    }
}

if ($hasGenericWrite) {
    Write-Output "PASS: svc_ldap has GenericWrite on svc_backup"
} else {
    Write-Output "FAIL: no GenericWrite grant found for svc_ldap on svc_backup"
    exit 1
}
