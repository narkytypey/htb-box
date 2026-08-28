$feature = (Get-WindowsFeature -Name Adcs-Web-Enrollment).InstallState
if ($feature -ne "Installed") {
    Write-Output "FAIL: Adcs-Web-Enrollment InstallState is '$feature', expected 'Installed'"
    exit 1
}
try {
    # AD CS Web Enrollment disables anonymous auth by default and requires
    # Negotiate/NTLM (confirmed on the live DC: anonymousAuthentication is
    # False, windowsAuthentication is True, WWW-Authenticate: Negotiate,NTLM).
    # That is the ESC8 precondition itself, not a misconfiguration to route
    # around -- use the caller's Windows identity so this check exercises the
    # same Negotiate/NTLM path the relay will.
    $resp = Invoke-WebRequest -Uri "http://localhost/certsrv/" -UseBasicParsing -UseDefaultCredentials -TimeoutSec 10
} catch {
    Write-Output "FAIL: GET http://localhost/certsrv/ threw: $_"
    exit 1
}
if ($resp.StatusCode -eq 200) {
    Write-Output "PASS: AD CS Web Enrollment is installed and certsrv answers 200"
} else {
    Write-Output "FAIL: GET http://localhost/certsrv/ returned $($resp.StatusCode), expected 200"
    exit 1
}
