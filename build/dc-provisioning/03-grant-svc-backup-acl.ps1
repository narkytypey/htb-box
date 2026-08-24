# GenericWrite, not a narrow WriteProperty scoped to userPrincipalName:
# ESC9 needs the attacker to enroll a certificate AS the victim, which
# requires first hijacking the victim's identity via a shadow credential
# (a write to msDS-KeyCredentialLink). A UPN-only WriteProperty grant
# would let the UPN-swap step work but not the shadow-credential step -
# GenericWrite covers both (spec S7).
dsacls "CN=svc_backup,OU=Service Accounts,DC=donerup,DC=htb" /G "DONERUP\svc_ldap:GW"
