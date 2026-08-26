$path = "C:\Users\Administrator\Desktop\root.txt"
if (Test-Path $path) {
    $content = (Get-Content $path -Raw).Trim()
    if ($content -match "^[a-f0-9]{32}$") {
        # SID-based ACL check (locale-independent). icacls prints localized
        # principal names on non-English Windows, so we resolve each ACE's
        # IdentityReference to its canonical SID instead of matching text.
        $administratorsSid = "S-1-5-32-544"
        $broadSids = @{
            "S-1-5-32-545" = "BUILTIN\Users"
            "S-1-1-0"      = "Everyone"
            "S-1-5-11"     = "Authenticated Users"
        }

        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        $domain = Get-ADDomain -ErrorAction SilentlyContinue
        if ($domain -and $domain.DomainSID) {
            $domainUsersSid = "$($domain.DomainSID.Value)-513"
            $broadSids[$domainUsersSid] = "Domain Users"
        }

        $acl = Get-Acl -Path $path
        $matchedBroad = $null
        $hasAdministrators = $false
        foreach ($ace in $acl.Access) {
            $sidValue = $null
            try {
                $sidValue = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
            } catch {
                # An untranslatable IdentityReference must not silently vanish from this gate --
                # emit evidence of the skip rather than let a broad grant hide behind it.
                Write-Output "WARN: skipping ACE with untranslatable identity '$($ace.IdentityReference)'"
                continue
            }

            if ($broadSids.ContainsKey($sidValue)) {
                $matchedBroad = "$($broadSids[$sidValue]) ($sidValue)"
            }
            if ($sidValue -eq $administratorsSid) {
                $hasAdministrators = $true
            }
        }

        if ($matchedBroad) {
            Write-Output "FAIL: root.txt ACL grants a broader principal than Administrators/SYSTEM ($matchedBroad)"
            exit 1
        } elseif (-not $hasAdministrators) {
            Write-Output "FAIL: root.txt ACL does not grant Administrators (SID $administratorsSid not found)"
            exit 1
        } else {
            Write-Output "PASS: root.txt exists with a 32-char hex flag"
        }
    } else {
        Write-Output "FAIL: root.txt content is not a 32-char hex string"
        exit 1
    }
} else {
    Write-Output "FAIL: root.txt not found at $path"
    exit 1
}
