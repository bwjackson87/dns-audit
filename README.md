---
> **Security & Sanitization Notice:** This repository contains sanitized, lab-safe code and documentation. It does not include proprietary, classified, sensitive, or employer-owned data. Hostnames, domains, usernames, IP addresses, and operational details are fictionalized or generalized. See [SECURITY_NOTICE.md](SECURITY_NOTICE.md) for full details.
---

# DNS Audit — Forward & Reverse Record Validator

## Overview
A PowerShell script that validates forward (A) and reverse (PTR) DNS records for every host in a domain machine list. It resolves each hostname to an IP, then resolves that IP back to a hostname, and flags any mismatches — exporting a timestamped CSV for review and remediation.

## Problem It Solves
Stale or mismatched DNS records cause silent, hard-to-trace connectivity failures across managed Windows domains. Without a systematic audit, these records accumulate unnoticed. This script was written after noticing anomalous DNS names during end-user connectivity troubleshooting — running it across all domain hosts revealed that **approximately 40% of machines had incorrect or stale DNS records**, which turned out to be the root cause of several long-standing, recurring network issues.

## Key Features
- Forward lookup (A record) + reverse lookup (PTR) for every host in the input CSV
- Match/Mismatch status per host with clear failure categorization
- Timestamped output CSV — reruns never overwrite prior results
- Handles lookup failures gracefully (no IP, no PTR, DNS timeout)
- No elevated privileges required — runs as a standard domain user
- Parameterized input/output paths — fully portable across environments

## Technologies Used
- PowerShell 5.1+
- `Resolve-DnsName` (built-in Windows DNS client)
- CSV input/output via `Import-Csv` / `Export-Csv`

## Example Use Case
An IT team is receiving sporadic help desk tickets about users unable to reach internal resources by name. Running this script against the full machine list surfaces 60+ hosts with stale PTR records pointing to old hostnames from a prior imaging cycle — giving the team a prioritized remediation list that closes out months of open tickets in a single afternoon.

## How to Run

```powershell
# Default — reads .\machines.csv, writes timestamped CSV to current directory
.\Invoke-DNSAudit.ps1

# Specify input file
.\Invoke-DNSAudit.ps1 -InputCsv "C:\Lists\all_machines.csv"

# Specify both input and output paths
.\Invoke-DNSAudit.ps1 -InputCsv ".\machines.csv" -OutputCsv "C:\Reports\dns_audit.csv"
```

**Input CSV format** (`machines.csv` template included in repo):

```csv
MachineName,DomainName
WORKSTATION01,corp.local
SERVER01,corp.local
```

## Example Output

**Console:**
```
DNS Audit complete.
  Total hosts  : 150
  Match        : 89
  Mismatch     : 61
  Results saved: .\DNSAuditResults_20260621_143055.csv
```

**Output CSV sample:**

| MachineName | FQDN | IP | Resolved_HostName | MatchStatus |
|---|---|---|---|---|
| WORKSTATION01 | WORKSTATION01.corp.local | 10.10.1.42 | WORKSTATION01.corp.local | Match |
| SERVER03 | SERVER03.corp.local | 10.10.1.87 | OLDSERVER03.corp.local | Mismatch |
| LAPTOP22 | LAPTOP22.corp.local | | | Mismatch |

## Security Notes
- Requires only **standard domain user** permissions — no admin rights needed
- Does not modify any DNS records — read-only audit only
- Output CSV may contain internal hostnames and IPs; treat as sensitive and store accordingly
- Authorized use only — run only against systems and domains you are authorized to audit

## Lessons Learned
- `Resolve-DnsName` returns multiple record types (A, CNAME, SOA); filtering to `Type -eq 'A'` is required to avoid grabbing a null IP from an unexpected record type
- Building FQDNs requires an explicit dot separator (`"$MachineName.$DomainName"`) — omitting it silently concatenates the strings and causes 100% lookup failure
- Comparing PTR results against the short `MachineName` instead of the full FQDN caused every record to report Mismatch, even correct ones
- Timestamped output filenames are essential for iterative audits — overwriting a prior run destroys the before/after comparison
