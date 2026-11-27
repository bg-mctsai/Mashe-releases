# Mashe bootstrap for: irm https://raw.githubusercontent.com/bg-mctsai/Mashe-releases/main/install.ps1 | iex
# Kept ASCII-only without a BOM: irm keeps the BOM and iex then fails, while installer\install.ps1 needs a BOM for its Chinese text.
# It finds the latest Mashe-releases Release, downloads that release's install.ps1 asset, checks it against the
# release's SHA256SUMS and runs it. The downloaded install.ps1 then verifies the content zip the same way (Mashe #171).
# Releases up to v1.6.0 were published without SHA256SUMS: for those it warns and continues. A newer release without it stops.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$tag = (Invoke-RestMethod 'https://api.github.com/repos/bg-mctsai/Mashe-releases/releases/latest' -UseBasicParsing).tag_name
if ($tag -notmatch '^v\d+\.\d+\.\d+$') { throw "Unexpected release tag: $tag" }
$base = "https://github.com/bg-mctsai/Mashe-releases/releases/download/$tag"
$id = [Guid]::NewGuid().ToString('N')
$script = Join-Path $env:TEMP ('MaBao-install-' + $id + '.ps1')
$sumsFile = Join-Path $env:TEMP ('MaBao-install-' + $id + '.sha256')
try {
  Invoke-WebRequest "$base/install.ps1" -OutFile $script -UseBasicParsing
  $hasSums = $true
  try {
    Invoke-WebRequest "$base/SHA256SUMS" -OutFile $sumsFile -UseBasicParsing
  } catch {
    # Windows PowerShell 5.1 throws WebException, PowerShell 7 throws HttpResponseException; both expose Response.StatusCode
    $response = $_.Exception.Response
    if (-not $response -or [int]$response.StatusCode -ne 404) { throw }
    $hasSums = $false
  }
  if ($hasSums) {
    $expected = ''
    foreach ($line in [IO.File]::ReadAllLines($sumsFile)) {
      if ($line -match '^([0-9a-fA-F]{64}) [ *]install\.ps1$') { $expected = $Matches[1].ToLowerInvariant() }
    }
    if (-not $expected) { throw "SHA256SUMS of $tag does not list install.ps1. Installation stopped." }
    $actual = (Get-FileHash -LiteralPath $script -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "SHA256 mismatch for install.ps1 of $tag (expected $expected, got $actual). The download may be corrupted or tampered with. Installation stopped." }
  } elseif ([version]$tag.Substring(1) -le [version]'1.6.0') {
    Write-Warning "$tag was published before SHA256SUMS existed; install.ps1 is not verified."
  } else {
    throw "Release $tag has no SHA256SUMS, so the download cannot be verified. Installation stopped."
  }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Tag $tag
} finally {
  Remove-Item -LiteralPath $script, $sumsFile -Force -ErrorAction SilentlyContinue
}
