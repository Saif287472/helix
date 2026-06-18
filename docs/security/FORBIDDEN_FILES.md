# Forbidden Files

Agents must not read, print, commit, or modify real secret material.

## Forbidden Patterns

- `.env`
- `.env.*` except `.env.example`
- `*.keystore`
- `*.jks`
- `*.p12`
- `*.pfx`
- `*.pem`
- `*.key`
- `*.crt`
- `*.cer`
- `*.csr`
- `service-account*.json`
- `google-services.json`
- `GoogleService-Info.plist`
- `firebase_options.dart`
- `secrets/**`
- `private/**`
- production signing configs
- local diagnostic exports containing user data

## Allowed Examples

- `.env.example` with placeholders only.
- Documentation that uses placeholder values such as `your-placeholder-value`.

If a task requires a forbidden file, stop and ask the user to perform that step
manually or provide a redacted sample.
