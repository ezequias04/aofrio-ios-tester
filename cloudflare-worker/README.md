# AoFrio no Cloudflare

Backend e portal hospedados em um Cloudflare Worker com banco relacional D1.

- Worker: `aofrio-refrigeration`
- D1: `aofrio-refrigeration-prod`
- Binding: `DB`
- Autenticação: `Authorization: Bearer <AOFRIO_API_TOKEN>`

## Desenvolvimento local

```bash
npx wrangler d1 execute aofrio-refrigeration-prod --local --file schema.sql
npx wrangler dev
```

## Build do aplicativo conectado ao portal

```bash
flutter build apk --dart-define=AOFRIO_API_TOKEN=SUA_CHAVE
flutter build ios --dart-define=AOFRIO_API_TOKEN=SUA_CHAVE
```

A URL de produção já é o valor padrão de `AOFRIO_API_URL`. Para outro ambiente,
forneça também `--dart-define=AOFRIO_API_URL=https://seu-endereco`.
