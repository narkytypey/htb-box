$val = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Kdc" `
    -Name "StrongCertificateBindingEnforcement" -ErrorAction SilentlyContinue).StrongCertificateBindingEnforcement
if ($val -eq 1) {
    Write-Output "PASS: StrongCertificateBindingEnforcement is weakened to 1"
} else {
    Write-Output "FAIL: StrongCertificateBindingEnforcement is '$val', expected 1"
    exit 1
}
