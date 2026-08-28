# ESC8 condition (spec docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md,
# Approach B): AD CS Web Enrollment (the certsrv HTTP endpoint) with no
# Extended Protection for Authentication is the actual vulnerability -- it
# is the default state after this install, so unlike
# 05-weaken-cert-binding.ps1 there is no separate "weaken" step: doing
# nothing extra here IS the misconfiguration.
$ErrorActionPreference = "Stop"

$feature = Get-WindowsFeature -Name Adcs-Web-Enrollment
if ($feature.InstallState -eq "Installed") {
    Write-Output "Adcs-Web-Enrollment already installed, skipping Install-WindowsFeature"
} else {
    Install-WindowsFeature Adcs-Web-Enrollment -IncludeManagementTools | Out-Null
    Write-Output "installed Adcs-Web-Enrollment"
}

# Install-AdcsWebEnrollment throws if already configured against this CA;
# same check-then-act idempotency as Install-AdcsCertificationAuthority in
# 04-install-adcs-esc9.ps1. The registry key that would seem to record this
# (HKLM:\SOFTWARE\Microsoft\Cryptography\CertSvc\Configuration\<CA>\Web
# Enrollment) does not actually exist on this box -- confirmed empirically:
# that whole CertSvc\Configuration hive under SOFTWARE is absent; the CA's
# real config lives under HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\
# Configuration instead (see 04-install-adcs-esc9.ps1), which has nothing to
# do with Web Enrollment. Detect the actual side effect of
# Install-AdcsWebEnrollment instead: it creates the CertSrv IIS virtual
# directory under the Default Web Site.
Import-Module WebAdministration
$webEnrollmentConfigured = Test-Path "IIS:\Sites\Default Web Site\CertSrv"
if ($webEnrollmentConfigured) {
    Write-Output "Web Enrollment already configured, skipping Install-AdcsWebEnrollment"
} else {
    Install-AdcsWebEnrollment -Force
    Write-Output "configured AD CS Web Enrollment for Donerup-CA"
}
