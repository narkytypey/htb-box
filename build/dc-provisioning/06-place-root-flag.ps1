# Per spec S10: root.txt lives on the DC, in the Administrator profile,
# placed once Domain Admin is achievable (Plan 3 Task 6).
$path = "C:\Users\Administrator\Desktop\root.txt"
# A re-run must not rotate a flag players may already hold -- same guard the
# user.txt generation in web/docker-entrypoint.sh uses. The ACL lockdown below
# is re-applied either way, so this script stays usable as a repair step.
if (Test-Path $path) {
    $status = "root.txt already present at $path, keeping the existing flag"
} else {
    $flag = ([guid]::NewGuid().Guid -replace '-', '')
    Set-Content -Path $path -Value $flag -NoNewline
    $status = "root.txt written to $path"
}
$aclOutput = icacls $path /inheritance:r /grant:r "Administrators:(R)" "SYSTEM:(F)"
if ($LASTEXITCODE -ne 0) {
    Write-Output $aclOutput
    Write-Output "FAIL: icacls did not apply the ACL lockdown on $path"
    exit 1
}
Write-Output $status
