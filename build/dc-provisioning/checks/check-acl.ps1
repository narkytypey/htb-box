$aclOutput = dsacls "CN=svc_backup,OU=Service Accounts,DC=donerup,DC=htb" | Select-String "svc_ldap"
if ($aclOutput -match "GENERIC_WRITE|GW") {
    Write-Output "PASS: svc_ldap has GenericWrite on svc_backup"
} else {
    Write-Output "FAIL: no GenericWrite grant found for svc_ldap on svc_backup"
    exit 1
}
