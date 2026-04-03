# Supabase and Updates

## Supabase-ready path

The running app currently uses the local runtime store so it stays fully testable on this machine without external credentials.

To switch the backend toward Supabase-backed storage, provide these values in `backend/.env`:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Recommended production pattern:
- anonymous or device-linked user identity
- row level security for every table
- realtime subscriptions for task, meeting, notification, and communication updates
- storage buckets only for attachments or audio artifacts

## GitHub-driven update manifest

The app checks release metadata from:
- local fallback: [app-update-manifest.json](d:/test/A.I app mobile/app-update-manifest.json)
- remote optional manifest: `GITHUB_UPDATE_MANIFEST_URL`

Recommended GitHub release flow:
- publish a new app build to GitHub Releases
- update a JSON manifest with `latestVersion`, `downloadUrl`, and `releaseNotes`
- point `GITHUB_UPDATE_MANIFEST_URL` to the raw JSON URL
- the Release Center will surface the new version inside the app

## Important mobile note

Android apps cannot silently replace themselves from GitHub without platform-level installation flow. The realistic production options are:
- Play Store in-app updates
- an OTA/update system such as Shorebird
- a GitHub-hosted APK plus an in-app prompt that sends the user through installation
