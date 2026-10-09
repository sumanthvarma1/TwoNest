# TwoNest implementation status

Updated: 2026-10-08

This checklist distinguishes working local-demo flows from production integrations. Local preview signup and seeded demo authentication are development-only and are not a production identity system.

## Milestone 1 — Foundation

- [x] Monorepo directories and contributor setup instructions
- [x] FastAPI app, SQLAlchemy models, SQLite local persistence and PostGIS Compose service
- [x] Initial Alembic migration and API docs through OpenAPI
- [x] Local development accounts and seed records for members, partner, experiences and properties
- [x] Email-based local preview signup creates a member and opens the onboarding flow; signup screen explains that verification is not connected
- [x] SwiftUI package source, five-tab member experience and Keychain token persistence
- [x] Independent Next.js member, restaurant partner and admin portals
- [x] Backend CI workflow
- [x] Setup, local role accounts, and API endpoint documentation
- [x] Simulator API URL configuration with an environment override for local-to-server deployment
- [ ] Production Sign in with Apple, magic links, phone verification and short-lived signed sessions
- [ ] Redis-backed background jobs, event outbox and WebSocket messaging
- [ ] Complete relational model coverage for the full product scope

## Milestone 2 — Profiles and matching

- [x] Profile edit/read API with intention, area, interests, privacy visibility, discovery pause and temporary travel mode
- [x] Authenticated onboarding API and iOS profile editor for 18+ age assurance, intentions, discovery radius, availability, accessibility/dietary needs and event budget
- [x] Grouped compatibility questionnaire with single/multi-select, scale, free-text and ranked answers plus per-answer importance, privacy and deal-breaker controls
- [x] Private compatibility answers drive scorer-backed introduction generation with mutual preference filters and a three-per-week cap
- [x] Development verification adapter with pending/approved/rejected states
- [x] Seeded, explainable introductions and mutual-interest gating
- [x] Deterministic weighted compatibility scorer with explainable reasons and age, intention, seeking, availability, visibility, history and deal-breaker filters
- [x] Matching decisions create a conversation only after both members opt in
- [x] Persistent member block/unblock with recommendations hidden in both directions and active conversations closed
- [ ] Admin-managed questionnaire/weight configuration, consented geospatial filtering and broader safety-restriction candidate filters
- [x] Saved seven-step onboarding with identity, intentions, mutual gender/age preferences, interests, availability, compatibility answers, review and first introduction generation
- [ ] Full profile media, granular field-level privacy and advanced preference settings
- [x] First-run welcome explains the product’s value: reasoned introductions, hosted dates/circles and later shared-home planning
- [x] Discovery cards present concrete introduction reasons without a misleading percentage or unsupported verification badge
- [x] iOS welcome, Home and Experiences use a forest-green/ivory editorial system, original illustrative lifestyle covers, API-backed experience listings and direct actions to Connect/Experiences
- [x] Connect first-use state explains the three-answer matching threshold and routes members to the questionnaire instead of implying an introduction is automatically on its way

## Milestone 3 — Messaging and experiences

- [x] Mutual-match inbox and individual chat screens, contextual conversation starters, local unread tracking, foreground polling, report/unmatch controls and closed-conversation handling
- [x] Messages first-use guidance routes members to introductions or experiences
- [x] Nest stage guidance for single members, optional partner invitation and dedicated Together/Home/Nest4 actions for couples
- [x] Native shaded 3D artwork, spring onboarding transitions and subtle perspective scroll motion with Reduce Motion support
- [x] Experience catalogue, capacity checks, bookings and check-in codes
- [x] iOS check-in, safety check-out and private post-event feedback actions
- [x] Role-scoped restaurant booking view and admin operations view
- [x] Moderator-only safety queue and case detail access
- [x] Four-person Nest4 text chat opens only after the meetup and four private positive follow-up decisions
- [ ] Real-time transport, attachment/voice messages, push, refunds and payment webhooks
- [x] Capacity-aware FIFO experience waitlist, member waitlist controls, booking cancellation and automatic place promotion
- [ ] Cancellation policy, seating/host assignment, partner payouts and managed venue reveal
- [x] Member report submission, block/unblock and unmatch actions in the iOS client and API
- [ ] Trusted-contact sharing, emergency assistance and staffed report-review workflow

## Rally — Standalone activity map

- [x] Standalone Rally main option with its own Map, My plans and Chats; shopping, hanging out, drinks, gaming and custom plans
- [x] In-person or online requests, start times, discovery windows and one to five companion places
- [x] Expiring availability by activity, mode and broad area, with an eligible available-member count for hosts
- [x] Join requests, host acceptance/decline, capacity enforcement, withdrawal, cancellation and completion
- [x] Participant-only Rally chat and meeting details, member reporting and block handling
- [x] Native MapKit map and place search, foreground device location, 1–50 km request/member search and opt-in expiring coarse map presence
- [x] Map-member invitations and capacity-aware acceptance, foreground WebSocket updates with reconnect and REST recovery
- [x] Walking/driving route distances and time estimates, transit-provider adapter, external bus/train planners, fare references, eligible NYC taxi meter baseline and Uber/Curb links
- [ ] Configure transit API credentials and exercise live itineraries/fares; approved in-app rideshare price/booking integration
- [ ] Background dispatch/APNs, cross-device unread state and shared pubsub for multiple backend workers

## Milestone 4 — Circles

- [x] Four-week guided Circle records, membership, prompt progression, local M4A voice reflections, group poll choices/tallies, member-only chat and proposed meet-ups with attendance voting
- [ ] Partner-venue booking for the week-four meetup and continued private groups after the four-week programme

## Milestone 5 — Couples and Nest4

- [x] iOS couple invitation and acceptance by the invited development account
- [x] Nest4 candidate list, proposal, four individual approvals, meetup attendance, private post-meet choices and consent-gated group chat in API and iOS
- [x] Couple publication consent, shared couple profile, TwoNest Together date/activity/milestone timeline; editing clears both partners' approvals
- [ ] Permanent group chat and fully weighted Nest4 preference matching with curated experience booking for the meetup

## Milestone 6 — Home Mode

- [x] iOS Home Mode consent collected independently from both couple members
- [x] Consent-gated Living Compatibility conversation report in API and iOS
- [x] Verified property catalogue and shared shortlist vote in API and iOS
- [x] Couple-scoped viewing request in API
- [x] Private per-partner home questionnaires, shared-answer alignment and compromise report
- [x] Couple-scoped moving checklist with shared task creation and completion, gated by both partners' Home Mode consent
- [ ] Map/commute search, property notes, applications, cost tools and neighbourhood dates
- [ ] Apartment partner property management and scoped viewing workflows

## Milestone 7 — Production readiness

- [x] Separate responsive member, partner and admin portal entry points with API role enforcement
- [ ] Complete admin moderation, appeal, partner verification, payments, audit and analytics tooling
- [ ] Provider adapters for payments, ID checks, SMS/email, maps, storage, analytics, errors and push
- [ ] Privacy manifest, sensitive-field encryption, retention/export/deletion jobs and security review
- [ ] StoreKit 2, APNs, accessibility audit, full iOS journey UI tests and performance review
- [ ] Backup/restore, deployment, threat-model and incident-response documentation

## Current demonstration path

1. Authenticate Alex and Sam using the local development endpoint.
2. Alex and Sam mark each other's introduction as interested; the second choice creates their conversation.
3. Exchange text, reserve a curated experience, check in/out and submit private feedback.
4. Alex invites Sam to a couple space; Sam accepts. Both independently activate Home Mode.
5. Read the consent-gated report, shortlist a verified property and request a viewing.
6. Create a second couple using Jamie and Riley. Propose Nest4 and collect all four approvals.
7. Sign into the partner and admin portals to view role-scoped bookings and operational counts.

Further work remains before the requested complete product and production deployment are complete. See unchecked items above.

## Verification run

- Backend acceptance/domain suite: `13 passed` (SQLite, local provider adapters; includes couple publication consent, shared timeline, waitlist promotion and the full Nest4 consent sequence).
- iOS simulator: TwoNest built, installed and launched on iPhone 17 Pro Simulator.
- iOS simulator: local preview signup reached the required profile editor using the new email-based development route.
- iOS: Xcode simulator build succeeded for the TwoNest app target.
- Web: production builds succeeded for member, partner and admin portals on Next.js 16.3.8.
- Alembic: migrations through `0012_couple_together` applied to local and simulator SQLite databases; independently approved couple profiles and shared moments are available in the current app.

## Guided entry and native motion update — 2026-10-08

- Signup and login are separate pages. Development signup rejects an existing email and directs the member to login. These remain local preview identity routes.
- New and unfinished accounts resume the saved onboarding step. `POST /onboarding/complete` validates the profile, discovery preferences, interests and at least three non-private compatibility answers before enabling discovery.
- Partner age preferences are checked in both directions. Private answers are excluded; a deal-breaker needs a matching, non-private counterpart answer.
- Migration `0013_guided_onboarding` applied to the local SQLite database. Existing non-demo accounts need to complete the guided flow.
- iOS simulator build succeeded. Welcome, signup, login, resumed onboarding and Messages first-use screens were inspected in the iPhone 17 Pro simulator. The previous 13-test result above predates this update; the test suite was not rerun for this change.
- Incoming chat uses foreground polling (8 seconds per open chat, 10 seconds in the inbox). Unread tracking is stored on this device; APNs, WebSockets and cross-device read receipts remain provider work.
- Debug builds remember an explicitly supplied `TWONEST_API_URL`. The current preview uses `http://localhost:8001`; the bundled default remains port 8000.
- Production sign-in, profile photos/storage, opted-in geocoding and push delivery are still outstanding. Preferred distance is saved, but without coordinates this preview uses coarse neighbourhood ranking rather than a kilometre cutoff.

## Up for update — 2026-10-08

- Migration `0014_activity_requests` applied to the local SQLite database. Requests, memberships, availability and chat messages persist in the backend.
- Adult members with completed onboarding can create and join requests. Host approval opens chat; meeting details are shown only to the host and accepted members.
- Request capacity changes are serialized in the database. Filling a plan closes remaining pending requests; leaving can reopen capacity. Blocks remove the relevant membership and hide blocked plans.
- Discovery uses exact, case-insensitive broad-area names and includes online plans. It does not calculate distance, travel time or an automatic match.
- The activity board polls while visible every 10 seconds; open plan detail polls every 6 seconds. Background notifications are not connected.
- Python source compilation and the Xcode simulator build succeeded. The activity board and creation form were inspected in the simulator. No test suite was run for this update; the earlier 13-test result does not cover activity requests.


## Rally map and live updates

- Rally is a separate main navigation destination. Home/Connect entry cards and activity conversations in dating Messages were removed. It uses the signed-in adult account, with independent availability, requests, memberships and chats; dating bios and compatibility preferences are excluded.
- Migration `0015_activity_map` adds coarse map presence and participant-only meeting coordinates. The backend performs geodesic radius checks on rounded discovery coordinates. Exact selected meetup locations are returned only to the host and accepted members.
- WebSocket `/activities/live` sends data-free refresh hints after committed activity changes and expiry ticks. REST access checks supply the actual data. Connections validate active account/adult eligibility; foreground clients reconnect after failures. This hub supports one API process; production horizontal scaling requires pubsub.
- Native walking/driving directions use MapKit. The Google Routes transit adapter supplies line/stop instructions and fares only if returned for the complete itinerary. No Google key is configured yet; native/external route planners are available as fallbacks. NYC base fares and taxi meter baselines are labelled separately from provider trip quotes.
- The Xcode simulator build and Python source compilation succeeded. Rally navigation, NYC/New Jersey map and the connected Live indicator were inspected in the simulator. Multi-client invitation/chat journeys, device GPS, complete route journeys, live transit responses and provider bookings were not exercised. No test suite was run for this update.
- Location permission copy and privacy-manifest location declarations were added. The wider production privacy/security audit is still outstanding.
