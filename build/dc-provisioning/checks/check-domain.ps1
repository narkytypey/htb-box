Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$domain = Get-ADDomain -ErrorAction SilentlyContinue
if ($domain -and $domain.DNSRoot -eq "donerup.htb") {
    Write-Output "PASS: domain donerup.htb is up ($($domain.DomainMode))"
    dcdiag /q
} else {
    Write-Output "FAIL: donerup.htb domain not found"
    exit 1
}
