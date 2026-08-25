# Per spec S10: root.txt lives on the DC, in the Administrator profile,
# placed once Domain Admin is achievable (Plan 3 Task 6).
$flag = ([guid]::NewGuid().Guid -replace '-', '')
$path = "C:\Users\Administrator\Desktop\root.txt"
Set-Content -Path $path -Value $flag -NoNewline
$aclOutput = icacls $path /inheritance:r /grant:r "Administrators:(R)" "SYSTEM:(F)"
if ($LASTEXITCODE -ne 0) {
    Write-Output $aclOutput
    Write-Output "FAIL: icacls did not apply the ACL lockdown on $path"
    exit 1
}
Write-Output "root.txt written to $path"
