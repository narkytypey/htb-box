# ESC9 condition (spec S8.1): the DC must be in the weak/compatibility
# binding mode, not the secure default (2).
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Kdc" `
    -Name "StrongCertificateBindingEnforcement" -Value 1 -Type DWord
Restart-Service kdc -Force
