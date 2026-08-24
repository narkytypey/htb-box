Install-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools
Install-AdcsCertificationAuthority `
    -CAType EnterpriseRootCA `
    -CACommonName "Donerup-CA" `
    -KeyLength 2048 `
    -HashAlgorithmName SHA256 `
    -Force

$templatesPath = "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=donerup,DC=htb"
$newTemplateName = "DonerupUserAuth"
$newTemplateDN = "CN=$newTemplateName,$templatesPath"

# Duplicate the built-in "User" template's attributes onto a new object.
$userTemplate = Get-ADObject -SearchBase $templatesPath -Filter "cn -eq 'User'" -Properties *
$excluded = @("cn", "distinguishedName", "name", "objectGUID", "whenCreated", "whenChanged", "uSNCreated", "uSNChanged")
$attrs = @{}
foreach ($p in $userTemplate.PropertyNames) {
    if ($p -notin $excluded) { $attrs[$p] = $userTemplate.$p }
}
New-ADObject -Name $newTemplateName -Type "pKICertificateTemplate" -Path $templatesPath -OtherAttributes $attrs

# ESC9 misconfiguration: strip the security-extension embedding so the
# issued certificate carries no szOID_NTDS_CA_SECURITY_EXT extension.
# 0x80000 = CT_FLAG_NO_SECURITY_EXTENSION.
$tmpl = Get-ADObject -Identity $newTemplateDN -Properties "msPKI-Enrollment-Flag"
Set-ADObject -Identity $newTemplateDN -Replace @{
    "msPKI-Enrollment-Flag" = ($tmpl."msPKI-Enrollment-Flag" -bor 0x80000)
}

# Grant Authenticated Users the Enroll extended right.
$enrollGuid = [GUID]"0e10c968-78fb-11d2-90d4-00c04f79dc55"
$acl = Get-Acl -Path "AD:\$newTemplateDN"
$sid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")  # Authenticated Users
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", $enrollGuid)
$acl.AddAccessRule($ace)
Set-Acl -Path "AD:\$newTemplateDN" -AclObject $acl

# Publish the template to the CA so it can actually be enrolled against.
certutil -SetCATemplates +DonerupUserAuth
