# 2026CCDC_DCT — Splunk Setup

Scripts I wrote and used as Splunk administrator for DunwoodyBlueTeam during CCDC 2026. Covers Universal Forwarder installs across Windows (PowerShell), Ubuntu 24, and Fedora 42, all forwarding into a central Splunk Enterprise indexer.

Make sure your indexes (`wineventlogs` and `linuxlogs`) and listening port (9997) are created on Splunk Enterprise before running anything.

## Scripts

| File | Description |
|------|-------------|
| `WinUF.ps1` | Windows UF install and config |
| `UbuUF.sh` | Ubuntu 24 UF install and config |
| `FedUf.sh` | Fedora 42 UF install and config |