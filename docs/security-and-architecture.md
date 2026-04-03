# Architecture Notes

## Threat Model Highlights
- No shared auth backend means device identity must be strongly isolated.
- PII-at-rest risk is mitigated by encrypting sensitive memory records.
- API abuse is constrained by rate limiting and strict payload validation.

## Data Flows
1. Flutter or React sends `x-device-id` header.
2. API ensures user partition exists in SQLite.
3. Writes are validated with Zod before DB access.
4. Sensitive memory text is encrypted before insert.

## Hardening Roadmap
- Add TLS termination (reverse proxy) for production.
- Add request signing from trusted mobile build.
- Add root/jailbreak detection and screenshot masking on sensitive views.
- Add secure backup and data wipe for lost devices.
