# Waiting Room — TP7 (multi-user management)

Flutter + Supabase waiting-room application from the cross-platform workshops,
extended for **TP7 — Ajouter la gestion multi-utilisateur**.

## What TP7 adds

- **Supabase Auth** with email/password: sign up, sign in, sign out and restored
  sessions.
- **Profiles**: a `profiles` row is created automatically for every account and
  is readable/updateable only by its owner.
- **User-owned queue entries**: every registration stores `user_id` and is
  created through the `register_queue_client` RPC, which takes the identity from
  the session instead of trusting the client.
- **Row Level Security**: signed-in users read the shared queue; inserts,
  updates and deletes are restricted to the owner. Anonymous access is removed.
- **My place in line**: the `queue_clients` view computes each entry's position
  and whether it belongs to the current user.
- **Realtime insert + delete**, pagination, offline persistence and automatic
  sync kept from Workshop 6.

Multi-tenancy was the optional part of the assignment and is **not** included.

## Project layout

```
lib/
├── main.dart                     # Supabase init, providers, auth gate
├── models/                       # Client, Profile, queue/connectivity enums
├── providers/
│   ├── auth_provider.dart        # session + profile state
│   ├── connectivity_provider.dart
│   └── queue_provider.dart       # queue, position, offline sync
├── repositories/queue_repository.dart
├── screens/
│   ├── auth_screen.dart
│   └── queue_screen.dart
├── services/                     # geolocation, connectivity, sync
├── storage/local_queue_storage.dart
└── widgets/                      # cards, offline banner, states
supabase/migrations/
├── 202611100001_workshop6_queue.sql
└── 202611170001_multi_user_auth.sql
```

## Database

The migration `202611170001_multi_user_auth.sql` is already applied to the
`waiting-room-app` Supabase project. To apply it elsewhere:

```sh
supabase db push
# or paste the file into the Supabase SQL Editor
```

It creates:

| Object | Purpose |
| --- | --- |
| `profiles` | Display name and timestamps per `auth.users` row |
| `clients.user_id` | Owner of each queue entry |
| `queue_clients` view | Name, position and `is_mine` for the shared queue |
| `register_queue_client` RPC | Authenticated, authoritative registration |
| Policies | Read the queue; write only your own entry |
| Broadcast triggers | Realtime insert and delete events |

## Run the app

The project URL and public anon key are already configured as defaults in
`lib/main.dart`.

```sh
flutter pub get
flutter run
# or override the backend:
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co \
            --dart-define=SUPABASE_PUBLISHABLE_KEY=your-public-key
```

Create an account on the sign-in screen, then join the queue. If your Supabase
project has **email confirmation** enabled, confirm the email before signing in
(Supabase Dashboard → Authentication → Providers → Email).

## Tests

```sh
flutter analyze
flutter test
```

## Known limits (by design for "basic auth")

- Every signed-in user can read the shared queue (that is the waiting-room
  contract). Names and positions are visible; nothing else is exposed.
- There is no staff/admin role, no tenant isolation, and no moderation dashboard.
- Offline registrations are stored per user and only synced for the account that
  created them.
