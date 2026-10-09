# TwoNest

**Meet your person. Build your home.** TwoNest is a relationship and home-building platform built around considered introductions, safe in-person experiences, couples and shared home planning.

## Repository

- `ios/TwoNest` — native SwiftUI client (iOS 17+).
- `backend` — FastAPI domain API, SQLAlchemy persistence and Alembic migrations.
- `web/member`, `web/partner`, `web/admin` — Next.js portal foundations.
- `docker-compose.yml` — Postgres/PostGIS and Redis for local development.
- `docs/IMPLEMENTATION_STATUS.md` — milestone checklist and known gaps.

## Run the API locally

```sh
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

The API uses SQLite by default for a zero-credential demo. Set `DATABASE_URL` to the Compose PostGIS URL to use PostgreSQL. OpenAPI is available at `/docs`. Seed demo data is created at startup; member accounts include `alex@twonest.test`, `sam@twonest.test`, `jamie@twonest.test`, and `riley@twonest.test`; staff/partner accounts include `partner@twonest.test`, `homes@twonest.test`, `host@twonest.test`, `moderator@twonest.test`, `support@twonest.test`, and `admin@twonest.test`. Development authentication is intentionally isolated under `/auth/dev-login` and must be disabled in production.

```sh
docker compose up -d db redis
cd backend && alembic upgrade head
```

## iOS

Open `ios/TwoNest` in Xcode, set the bundle identifier and signing team, then run on an iOS 17+ simulator. The app points at `http://localhost:8000`; for a physical device, configure the API base URL to the development machine's LAN address. Sign in with one of the development accounts. Apple authentication and production provider credentials are integration points, not represented as working credentials in this local demo.

## Portals

Each portal is an independent Next.js app so partner and operations permissions can be deployed separately. Install all three workspaces once from `web`, then run the chosen portal:

```sh
cd web
npm install
npm run dev --workspace=twonest-member
npm run dev --workspace=twonest-partner
npm run dev --workspace=twonest-admin
```

They use ports 3000, 3001 and 3002 respectively. All service secrets belong in environment variables; see `.env.example`.

## Production notes

Do not expose the development login or seeded demo identities in a production deployment. Configure TLS, managed secrets, backups, retention and deletion jobs, provider adapters, administrative MFA, operational monitoring, and a reviewed privacy/security policy before handling real member data.

### iOS guided preview

The welcome screen has separate signup and login pages. New accounts complete saved onboarding before discovering members. No production identity provider is connected yet.

If another service occupies port 8000, run the backend on port 8001 and launch the simulator app with an override:

```sh
SIMCTL_CHILD_TWONEST_API_URL=http://localhost:8001 xcrun simctl launch booted com.twonest.app
```

Debug builds remember the supplied URL across launches. You can override it again from the Xcode scheme’s `TWONEST_API_URL` environment variable. Apply backend migrations with `.venv/bin/alembic upgrade head` before starting the API.

### Rally — standalone activity map

Open **Rally** in the main bottom navigation. It has its own **Map**, **My plans** and **Chats** sections, separate from dating introductions, Messages, Experiences and Nest. It shares the signed-in adult member account; dating bios, preferences and compatibility scores are not used in Rally.

The NYC / New Jersey map searches requests and opt-in available people within 1–50 km. Search an area or use foreground device location. Member presence uses a fixed rounded grid and expires with availability. Exact meetup coordinates are visible only to hosts and accepted participants. Tap a person to invite them to an open plan; accepting the invitation claims a place and opens Rally chat. Other members can still ask to join public requests for host approval.

Rally uses authenticated WebSockets for foreground updates, with reconnect and REST recovery. The current event hub runs in one backend process. Before scaling to multiple workers/replicas, replace the local hub with Redis/pubsub and add APNs for background delivery.

**Get there** compares MapKit walking/driving routes and distance/time estimates, offers transit planners, Uber destination links and cab-provider links. It shows the MTA local base-fare reference separately from trip totals. Standard eligible NYC taxi journeys have a labelled distance-based meter baseline, excluding variable charges. New Jersey, airport and cross-state cab trips need a provider quote.

Provider setup:

- Set server-only `GOOGLE_ROUTES_API_KEY` in the backend environment with Routes API enabled, billing and restricted quotas for in-app bus/train steps and provider-supplied complete-itinerary fares. The adapter is implemented, but no key is configured in this preview. Transit fares may be unavailable even when routes exist. Without a key, users can open Apple/Google Maps and agency fare pages.
- Optionally set `UBER_CLIENT_ID` in the iOS Info.plist for Uber attribution. Live in-app Uber price/vehicle quotes and ride booking require approved provider access; the current app opens the provider flow and does not book or charge.
- Native MapKit place search, maps and walking/driving routes need no additional API key in this iOS build.
- APNs credentials, production identity and managed realtime infrastructure remain production integrations.

Apply migration `0015_activity_map` before running this version. No fake people, route times or Uber fares are generated to populate the map.
