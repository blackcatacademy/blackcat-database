# Secrets Policy

- Keep secrets only in `secrets/*.enc.yaml` (SOPS-encrypted).  
- Never commit plaintext `.env` with credentials.  
- CI checks for plaintext secrets & common token patterns.

## Encrypt
```bash
sops -e secrets/dev.enc.yaml > secrets/dev.enc.yaml
```
