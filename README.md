# DNS Audit — Forward & Reverse Record Validator

A PowerShell script that runs forward (A) and reverse (PTR) DNS queries against every host in a domain machine list, flags records where the two results don't match, and exports a timestamped CSV for analysis.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell) ![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey?logo=windows) ![License](https://img.shields.io/badge/License-MIT-green)

## Background

This script was written after noticing anomalous DNS names while troubleshooting end-user connectivity issues on a managed Windows domain. Running it across all domain hosts revealed that approximately **40% of machines had incorrect or stale DNS records** — a root cause behind several major and recurring network problems in the organization. The mismatch report gave the team a prioritized list to resolve, closing out an issue that had been open for an extended period.

## What It Does

For each host in the input CSV:

1. Constructs the **FQDN** from `MachineName` + `.` + `DomainName`
2. **Forward lookup** — resolves the FQDN to an IP address (A record only)
3. **Reverse lookup** — resolves that IP back to a hostname (PTR record)
4. **Compares** the PTR result against the FQDN and marks `Match` or `Mismatch`
5. Exports all results to a **timestamped CSV** (reruns never overwrite prior results)

## Requirements

| Requirement | Detail |
|-------------|--------|
| PowerShell | 5.1 or later |
| Network | DNS resolution access to the domain's name servers |
| Permissions | Standard domain user — no elevated rights needed |

## Usage

```powershell
# Default — reads .\machines.csv, writes timestamped CSV to current directory
.\Invoke-DNSAudit.ps1

# Specify input file
.\Invoke-DNSAudit.ps1 -InputCsv "C:\Lists\all_machines.csv"

# Specify both input and output
.\Invoke-DNSAudit.ps1 -InputCsv ".\all_machines.csv" -OutputCsv "C:\Reports\dns_audit.csv"
```

### Input CSV format

The input file must contain at minimum `MachineName` and `DomainName` columns. The remaining columns are written by the script and can be blank placeholders:

```csv
MachineName,DomainName,FQDN,IP,Resolved_HostName,Status1,Status2,MatchStatus
WORKSTATION01,corp.local,,,,,,
WORKSTATION02,corp.local,,,,,,
SERVER01,corp.local,,,,,,
```

A ready-to-use `machines.csv` template is included in this repo.

### Example Output

```
DNS Audit complete.
  Total hosts  : 150
  Match        : 89
  Mismatch     : 61
  Results saved: .\DNSAuditResults_20260621_143055.csv
```

Sample output CSV row:

| MachineName | DomainName | FQDN | IP | Resolved_HostName | Status1 | Status2 | MatchStatus |
|---|---|---|---|---|---|---|---|
| WORKSTATION01 | corp.local | WORKSTATION01.corp.local | 10.10.1.42 | WORKSTATION01.corp.local | Success | Success | Match |
| SERVER03 | corp.local | SERVER03.corp.local | 10.10.1.87 | OLDSERVER03.corp.local | Success | Success | Mismatch |
| LAPTOP22 | corp.local | LAPTOP22.corp.local | | | Fail | Skipped — no IP | Mismatch |

## Bugs Fixed from Original Version

| # | Bug | Impact | Fix |
|---|-----|--------|-----|
| 1 | FQDN built without a dot separator: `PC001corp.local` | All forward lookups fail | Changed to `"$MachineName.$DomainName"` |
| 2 | Forward lookup queried the short `MachineName` instead of the FQDN | Could resolve against wrong DNS search suffix | Changed to query `$row.FQDN` |
| 3 | Reverse lookup compared PTR result (full FQDN) against short `MachineName` | **Every record reported Mismatch**, even correct ones | Changed comparison to `$row.FQDN`, case-insensitive |
| 4 | `Resolve-DnsName` result not filtered by record type — `.IPAddress[0]` could grab a null from a CNAME or SOA record | Silent wrong IP or null-dereference error | Added `Where-Object { $_.Type -eq 'A' }` filter |
| 5 | Reverse lookup attempted even when `$row.IP` was empty | Confusing unrelated error masked the real forward-lookup failure | Added guard: skip reverse block entirely if IP is blank |
| 6 | Input/output paths hardcoded with a real username | Not portable; exposed PII | Converted to `-InputCsv` / `-OutputCsv` parameters |
| 7 | No existence check on input file | Unhelpful error from `Import-Csv` | Added `Test-Path` guard |
| 8 | Output file overwritten on every rerun | Prior results lost | Timestamp appended to output filename automatically |

## License

MIT — see [LICENSE](LICENSE) for details.
