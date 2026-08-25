$path = "C:\Users\Administrator\Desktop\root.txt"
if (Test-Path $path) {
    $content = (Get-Content $path -Raw).Trim()
    if ($content -match "^[a-f0-9]{32}$") {
        Write-Output "PASS: root.txt exists with a 32-char hex flag"
    } else {
        Write-Output "FAIL: root.txt content is not a 32-char hex string"
        exit 1
    }
} else {
    Write-Output "FAIL: root.txt not found at $path"
    exit 1
}
