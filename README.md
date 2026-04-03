# AI Personal Chief

Premium command-center workspace for personal operations, built with a live Node backend, a React control surface, and a Flutter mobile client.

## What works now
- Executive command center with premium sidebar/topbar shell
- Realtime workspace feed via server-sent events
- Priority engine with task lifecycle updates
- Agenda timeline and meeting scheduling
- Communication triage with urgency analysis
- Context-aware auto-reply generation
- Decision cockpit with saved recommendations
- Encrypted memory vault
- Habit tracking and check-ins
- VIP contact routing and emergency override
- Update center with GitHub-manifest-compatible release checks
- Distinct per-device workspaces and seeded user data

## Run
```bash
cd backend
npm install
npm run dev
```

```bash
cd web_react
npm install
npm run dev
```

```bash
cd mobile_flutter
flutter pub get
flutter run
```

## Current runtime
- Backend: `http://127.0.0.1:8080`
- Web app: `http://127.0.0.1:5173`

## Supabase and release updates
- Backend is `Supabase-ready` through environment variables in [backend/.env.example](d:/test/A.I app mobile/backend/.env.example)
- Update metadata is driven by [app-update-manifest.json](d:/test/A.I app mobile/app-update-manifest.json)
- Detailed setup notes live in [supabase-and-updates.md](d:/test/A.I app mobile/docs/supabase-and-updates.md)
