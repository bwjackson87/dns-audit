<#
.SYNOPSIS
    Runs forward and reverse DNS queries against a list of domain hosts and
    flags records where the results do not match.

.DESCRIPTION
    For each machine in the input CSV the script:

      1. Constructs the FQDN from MachineName + "." + DomainName
      2. Forward lookup  — resolves the FQDN to an IP address (A record only)
      3. Reverse lookup  — resolves that IP back to a hostname (PTR record)
      4. Compares the PTR result against the FQDN and marks Match / Mismatch

    Results are written to a timestamped CSV so every run is preserved.

    Background:
    This script was written after noticing anomalous DNS names while
    troubleshooting end-user issues on a managed Windows domain. Running it
    against all domain hosts revealed that roughly 40 % of machines had
    incorrect or stale DNS records — a root cause behind several recurring
    and unresolved network connectivity problems across the organization.

.PARAMETER InputCsv
    Path to the input CSV. Must contain columns: MachineName, DomainName.
    Additional columns (FQDN, IP, Resolved_HostName, Status1, Status2,
    MatchStatus) are added/updated by this script.
    Default: ".\machines.csv"

.PARAMETER OutputCsv
    Path for the results CSV. A timestamp is automatically appended so
    reruns never overwrite previous results.
    Default: ".\DNSAuditResults_<timestamp>.csv"

.EXAMPLE
    .\Invoke-DNSAudit.ps1

.EXAMPLE
    .\Invoke-DNSAudit.ps1 -InputCsv ".\all_machines.csv" -OutputCsv "C:\Reports\dns_audit.csv"

.NOTES
    Requirements:
      - PowerShell 5.1 or later
      - DNS resolution access to the domain's DNS servers
      - The running account needs no special privileges — standard domain
        user read access to DNS is sufficient
#>

[CmdletBinding()]
param (
    [string] $InputCsv  = ".\machines.csv",
    [string] $OutputCsv
)

# ---------------------------------------------------------------------------
# Validate input
# ---------------------------------------------------------------------------

if (-not (Test-Path $InputCsv)) {
    Write-Error "Input file not found: $InputCsv"
    exit 1
}

$csvData = Import-Csv -Path $InputCsv

if (-not $csvData) {
    Write-Error "No data found in '$InputCsv'."
    exit 1
}

# Build output path with timestamp so reruns never overwrite prior results
if (-not $OutputCsv) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputCsv = ".\DNSAuditResults_$timestamp.csv"
}

# ---------------------------------------------------------------------------
# DNS audit loop
# ---------------------------------------------------------------------------

$total   = $csvData.Count
$current = 0

foreach ($row in $csvData) {
    $current++
    Write-Progress -Activity "DNS Audit" `
                   -Status "$($row.MachineName) ($current of $total)" `
                   -PercentComplete (($current / $total) * 100)

    # Bug fix #1 — original code concatenated without a dot:
    #   $row.MachineName + $row.DomainName  →  "PC001corp.local"
    # Correct:
    $row.FQDN = "$($row.MachineName).$($row.DomainName)"

    # ------------------------------------------------------------------
    # Forward lookup — FQDN → IP (A record)
    # ------------------------------------------------------------------
    # Bug fix #2 — original queried the short MachineName, not the FQDN,
    #   which could resolve against the wrong DNS search suffix.
    # Bug fix #4 — Resolve-DnsName returns multiple record types (A, CNAME,
    #   SOA, NS …); blindly indexing [0] can return null or a non-IP type.
    #   Filter for Type -eq 'A' and take the first result.
    try {
        $aRecord = Resolve-DnsName -Name $row.FQDN -Type A -ErrorAction Stop |
                   Where-Object { $_.Type -eq 'A' } |
                   Select-Object -First 1

        if ($aRecord) {
            $row.IP      = $aRecord.IPAddress
            $row.Status1 = "Success"
        }
        else {
            # Query succeeded but returned no A record (e.g. CNAME-only)
            $row.IP      = ""
            $row.Status1 = "No A Record"
        }
    }
    catch {
        $row.IP      = ""
        $row.Status1 = "Fail — $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # Reverse lookup — IP → hostname (PTR record)
    # ------------------------------------------------------------------
    # Bug fix #5 — original attempted the reverse lookup even when $row.IP
    #   was empty (forward lookup failed), causing a confusing unrelated error.
    if ($row.IP) {
        try {
            # Resolve-DnsName on an IP address returns PTR records whose
            # hostname is in the NameHost property.
            $ptrRecord = Resolve-DnsName -Name $row.IP -Type PTR -ErrorAction Stop |
                         Where-Object { $_.Type -eq 'PTR' } |
                         Select-Object -First 1

            $resolvedFQDN        = $ptrRecord.NameHost
            $row.Resolved_HostName = $resolvedFQDN

            $row.Status2 = if ($resolvedFQDN) { "Success" } else { "No PTR Record" }

            # Bug fix #3 — original compared the PTR result (a full FQDN like
            #   "PC001.corp.local") against $row.MachineName (the short name
            #   "PC001"), so EVERY record appeared as a Mismatch even when
            #   forward and reverse DNS were correct.
            # Correct: compare against $row.FQDN, case-insensitively.
            if ($resolvedFQDN -and ($resolvedFQDN.TrimEnd('.') -ieq $row.FQDN)) {
                $row.MatchStatus = "Match"
            }
            else {
                $row.MatchStatus = "Mismatch"
            }
        }
        catch {
            $row.Resolved_HostName = ""
            $row.Status2           = "Fail — $($_.Exception.Message)"
            $row.MatchStatus       = "Mismatch"
        }
    }
    else {
        # No IP from forward lookup — skip reverse, mark accordingly
        $row.Resolved_HostName = ""
        $row.Status2           = "Skipped — no IP"
        $row.MatchStatus       = "Mismatch"
    }
}

Write-Progress -Activity "DNS Audit" -Completed

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

$csvData | Export-Csv -Path $OutputCsv -NoTypeInformation

# Summary stats
$total    = $csvData.Count
$matches  = ($csvData | Where-Object { $_.MatchStatus -eq "Match" }).Count
$mismatches = $total - $matches

Write-Host ""
Write-Host "DNS Audit complete." -ForegroundColor Cyan
Write-Host "  Total hosts  : $total"
Write-Host "  Match        : $matches"  -ForegroundColor Green
Write-Host "  Mismatch     : $mismatches" -ForegroundColor $(if ($mismatches -gt 0) { "Red" } else { "Green" })
Write-Host "  Results saved: $OutputCsv"
