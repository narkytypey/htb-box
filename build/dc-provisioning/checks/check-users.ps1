Import-Module ActiveDirectory

$failures = 0

$admin = Get-ADUser -Identity administrator -Properties info -ErrorAction SilentlyContinue
if ($null -eq $admin) {
    Write-Output "FAIL: administrator account not found (domain not provisioned?)"
    $failures++
} elseif ($null -ne $admin.info) {
    Write-Output "FAIL: administrator.info is set to '$($admin.info)' - must be absent (spec S4.1)"
    $failures++
} else {
    Write-Output "PASS: administrator.info is absent"
}

$jdoe = Get-ADUser -Identity jdoe -Properties info -ErrorAction SilentlyContinue
if ($null -eq $jdoe) {
    Write-Output "FAIL: jdoe does not exist"
    $failures++
} elseif ($jdoe.info -eq "SogukDonerAyran7") {
    Write-Output "PASS: jdoe.info carries the legacy credential"
} else {
    Write-Output "FAIL: jdoe.info is '$($jdoe.info)', expected SogukDonerAyran7"
    $failures++
}

foreach ($name in @("svc_ldap", "svc_backup")) {
    if (Get-ADUser -Identity $name -ErrorAction SilentlyContinue) {
        Write-Output "PASS: $name exists"
    } else {
        Write-Output "FAIL: $name does not exist"
        $failures++
    }
}

if ($failures -gt 0) { exit 1 }
