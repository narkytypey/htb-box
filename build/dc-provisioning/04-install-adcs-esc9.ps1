# Stop on the first failure. The previous version ran straight through a failed
# New-ADObject and then emitted five cascading errors against an object that had
# never been created, ending with a misleading "certutil FAILED".
$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory

$templatesPath   = "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=donerup,DC=htb"
$newTemplateName = "DonerupUserAuth"
$newTemplateDN   = "CN=$newTemplateName,$templatesPath"

# --- CA role -----------------------------------------------------------
Install-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools | Out-Null

# Install-AdcsCertificationAuthority throws if a CA is already configured, so
# make re-runs safe: the ADCSAdministration provider reports the configured CA.
# Uninstalling the CA role leaves its private key container behind, so a
# re-install after a teardown otherwise dies with "The private key
# 'Donerup-CA' already exists" -- hence -OverwriteExistingKey below. Minting
# a fresh key is the intent on a re-run anyway: the only reason to tear the CA
# down is that the material it holds is wrong.
$caConfigured = $null -ne (Get-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration" `
    -Name Active -ErrorAction SilentlyContinue)
if ($caConfigured) {
    Write-Output "CA already configured, skipping Install-AdcsCertificationAuthority"
} else {
    Install-AdcsCertificationAuthority `
        -CAType EnterpriseRootCA `
        -CACommonName "Donerup-CA" `
        -KeyLength 2048 `
        -HashAlgorithmName SHA256 `
        -OverwriteExistingKey `
        -Force
    Write-Output "installed Enterprise Root CA 'Donerup-CA'"
}

# --- Template ----------------------------------------------------------
# Modelled on the built-in "User" template, but copying an explicit attribute
# list rather than every PropertyNames entry: a blind copy drags in nulls and
# operational attributes (instanceType, objectCategory, uSNCreated, ...) and
# New-ADObject rejects the whole hashtable with "the argument is null or an
# element of the argument collection contains a null value".
$user = Get-ADObject -SearchBase $templatesPath -LDAPFilter "(cn=User)" -Properties *
if (-not $user) { throw "built-in User certificate template not found under $templatesPath" }

$copied = @(
    "flags",
    "pKICriticalExtensions",
    "pKIDefaultCSPs",
    "pKIDefaultKeySpec",
    "pKIExpirationPeriod",
    "pKIOverlapPeriod",
    "pKIKeyUsage",
    "pKIMaxIssuingDepth",
    "msPKI-Minimal-Key-Size",
    "msPKI-Private-Key-Flag",
    "msPKI-RA-Signature"
)

$attrs = @{}
foreach ($p in $copied) {
    $v = $user.$p
    if ($null -eq $v) { throw "expected attribute '$p' is absent on the User template" }
    $attrs[$p] = $v
}

# CT_FLAG_AUTO_ENROLLMENT (0x20) on `flags` would have every domain user pull
# this certificate on its own. Players should enrol deliberately, so clear it.
$attrs["flags"] = $user.flags -band (-bnot 0x20)

# Each template needs its own OID under the forest's PKI OID arc; reusing the
# User template's would make the CA treat the two as the same template.
$oidContainer = Get-ADObject -Identity "CN=OID,CN=Public Key Services,CN=Services,CN=Configuration,DC=donerup,DC=htb" `
    -Properties "msPKI-Cert-Template-OID" -ErrorAction SilentlyContinue
if ($oidContainer -and $oidContainer."msPKI-Cert-Template-OID") {
    $forestOid = $oidContainer."msPKI-Cert-Template-OID"
} else {
    # Fall back to the arc the built-in templates already sit on, minus their
    # trailing "<set>.<id>" pair.
    $forestOid = ($user."msPKI-Cert-Template-OID" -split "\." | Select-Object -SkipLast 3) -join "."
}
$rand = New-Object System.Random
$attrs["msPKI-Cert-Template-OID"] = "$forestOid.$($rand.Next(1000000,99999999)).$($rand.Next(1000000,99999999))"

# Schema version 2: v1 templates cannot carry msPKI-Certificate-Application-Policy,
# and certipy's ESC9 detection reads the application policy, not just the EKU.
$attrs["msPKI-Template-Schema-Version"]  = 2
$attrs["msPKI-Template-Minor-Revision"]  = 0
$attrs["revision"]                       = 100
$attrs["displayName"]                    = "Donerup User Auth"

# Client Authentication only. The User template also carries EFS
# (1.3.6.1.4.1.311.10.3.4) and Secure Email (1.3.6.1.5.5.7.3.4); neither is
# needed for the PKINIT step and Secure Email drags in the email requirement
# handled below.
$attrs["pKIExtendedKeyUsage"]                  = @("1.3.6.1.5.5.7.3.2")
$attrs["msPKI-Certificate-Application-Policy"] = @("1.3.6.1.5.5.7.3.2")

# The User template's name flag is 0xA6000000, which includes
# CT_FLAG_SUBJECT_REQUIRE_EMAIL (0x20000000) and
# CT_FLAG_SUBJECT_ALT_REQUIRE_EMAIL (0x04000000). None of the domain accounts
# have a `mail` attribute, so enrolment would fail with "The email name is
# unavailable and cannot be added to the Subject or Subject Alternate name."
# Keep only CT_FLAG_SUBJECT_REQUIRE_DIRECTORY_PATH (0x80000000) and
# CT_FLAG_SUBJECT_ALT_REQUIRE_UPN (0x02000000) -- the UPN in the SAN is what
# ESC9 pivots on. 0x82000000 does not fit in a signed 32-bit integer, which is
# what AD stores, hence the negative literal.
$attrs["msPKI-Certificate-Name-Flag"] = -2113929216   # 0x82000000

# THE misconfiguration (spec S7): CT_FLAG_NO_SECURITY_EXTENSION (0x00080000).
# Without the szOID_NTDS_CA_SECURITY_EXT extension the KDC falls back to
# mapping the certificate by UPN, so an attacker who can rewrite a victim's UPN
# can authenticate as whoever that UPN now points at.
$attrs["msPKI-Enrollment-Flag"] = 0x00080000

$existing = Get-ADObject -LDAPFilter "(cn=$newTemplateName)" -SearchBase $templatesPath -ErrorAction SilentlyContinue
if ($existing) {
    Write-Output "template $newTemplateName already present, updating its attributes"
    Set-ADObject -Identity $newTemplateDN -Replace $attrs
} else {
    New-ADObject -Name $newTemplateName -Type "pKICertificateTemplate" -Path $templatesPath -OtherAttributes $attrs
    Write-Output "created template $newTemplateName"
}

# --- Enrollment rights -------------------------------------------------
$enrollGuid = [GUID]"0e10c968-78fb-11d2-90d4-00c04f79dc55"
$acl = Get-Acl -Path "AD:\$newTemplateDN"
$sid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")  # Authenticated Users
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", $enrollGuid)
$acl.AddAccessRule($ace)
Set-Acl -Path "AD:\$newTemplateDN" -AclObject $acl
Write-Output "granted Enroll to Authenticated Users on $newTemplateName"

# --- Publish to the CA -------------------------------------------------
# The CA caches the template list; without the restart certutil can publish a
# template the CA then refuses to issue against until it next starts.
& certutil -SetCATemplates "+$newTemplateName"
if ($LASTEXITCODE -ne 0) { throw "certutil -SetCATemplates failed with exit code $LASTEXITCODE" }
Restart-Service CertSvc
Write-Output "published $newTemplateName to the CA and restarted CertSvc"
