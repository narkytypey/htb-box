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


$rosterPath = Join-Path $PSScriptRoot "..\data\employees.csv"
if (-not (Test-Path $rosterPath)) {
    Write-Output "FAIL: roster CSV not found at $rosterPath"
    $failures++
} else {
    $roster = Import-Csv $rosterPath

    foreach ($row in $roster) {
        $u = Get-ADUser -LDAPFilter "(sAMAccountName=$($row.sam))" -Properties info, title, employeeID -ErrorAction SilentlyContinue
        if ($null -eq $u) {
            Write-Output "FAIL: roster account $($row.sam) does not exist"
            $failures++
            continue
        }
        if ($null -ne $u.info) {
            Write-Output "FAIL: $($row.sam).info is set - only jdoe may carry an info value"
            $failures++
        }
        if ($u.employeeID -ne $row.employee_id) {
            Write-Output "FAIL: $($row.sam).employeeID is '$($u.employeeID)', expected $($row.employee_id)"
            $failures++
        }
    }
    if ($failures -eq 0) {
        Write-Output "PASS: all $($roster.Count) roster accounts present, no info values, employeeIDs match"
    }

    # Constraint C1: ldap_auth.is_privileged is a substring match on
    # "Domain Admins", so a group or OU carrying that substring would hand
    # app-admin to its members without the LDAP injection.
    $badNames = @()
    $badNames += (Get-ADGroup -Filter * | Where-Object { $_.Name -like "*Domain Admins*" -and $_.Name -ne "Domain Admins" }).Name
    $badNames += (Get-ADOrganizationalUnit -Filter * | Where-Object { $_.Name -like "*Domain Admins*" }).Name
    # `(Get-ADGroup ...).Name` yields $null when nothing matches, and
    # `+= $null` appends a null *element* -- so without this compaction the
    # array is Count 2 on a clean domain and the assertion false-FAILs.
    $badNames = @($badNames | Where-Object { $_ })
    if ($badNames.Count -gt 0) {
        Write-Output "FAIL: names containing the 'Domain Admins' substring: $($badNames -join ', ')"
        $failures++
    } else {
        Write-Output "PASS: no group or OU name shadows the 'Domain Admins' substring"
    }

    # No filler account may hold a privileged membership.
    $privileged = @("Domain Admins", "Enterprise Admins", "Administrators", "Account Operators", "Backup Operators")
    foreach ($groupName in $privileged) {
        $members = (Get-ADGroupMember -Identity $groupName -Recursive -ErrorAction SilentlyContinue).SamAccountName
        foreach ($row in $roster) {
            if ($members -contains $row.sam) {
                Write-Output "FAIL: roster account $($row.sam) is a member of $groupName"
                $failures++
            }
        }
    }
    Write-Output "PASS: no roster account holds a privileged group membership"
}

if ($failures -gt 0) { exit 1 }
