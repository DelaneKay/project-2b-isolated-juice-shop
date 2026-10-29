# Nuclei DAST result

- Target: `http://10.30.20.52:3000` (private Juice Shop lab host)
- Scanner: Nuclei v3.11.1, run from scanner EC2 `i-03e2af14e0abfd20d` (`10.30.10.223`).
- App: Juice Shop EC2 `i-0553f724dcdade47e` (`10.30.20.52`).
- Result captured: 2026-10-27
- Outcome: one informational Swagger API documentation endpoint found at `/api-docs/swagger.json`.

The endpoint discovery is an informational observation and is not proof of an exploitable vulnerability. This artifact was transcribed from terminal output supplied during the lab; it is not a complete JSONL export. Juice Shop is intentionally vulnerable and must remain isolated.
