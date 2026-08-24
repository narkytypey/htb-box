Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName "donerup.htb" `
    -DomainNetbiosName "DONERUP" `
    -InstallDns:$true `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "R00tP@ssw0rd2026!" -AsPlainText -Force) `
    -Force:$true
# The VM reboots automatically to complete promotion.
