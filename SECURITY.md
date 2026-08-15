# Security Policy

## Supported versions

Security fixes are applied to the latest revision of the `main` branch. The project does not currently maintain backported release branches.

## Reporting a vulnerability

Do not disclose a suspected vulnerability in a public issue. Use GitHub's private vulnerability reporting feature for this repository. If that feature is unavailable, contact the maintainer through the public contact method listed on the maintainer's GitHub profile and request a private reporting channel.

Include the affected commit, impacted module, reproduction conditions, potential impact, and any proposed mitigation. Avoid sending operational data, credentials, proprietary protocol documents, or information that you are not authorized to share.

The maintainer will acknowledge a complete report when available, investigate it, and coordinate disclosure after a fix is ready. No response-time guarantee is currently provided.

## Scope

The project is a research HDL implementation and has not been independently audited or certified. Reports about RTL logic, unsafe parameter combinations, malformed-frame handling, denial of service, and data/control misalignment are in scope. Vulnerabilities in Vivado or generated Xilinx IP should also be reported to the relevant vendor.
