# TwoNest API notes

FastAPI exposes an OpenAPI 3 schema at `/openapi.json` and interactive docs at `/docs` while running locally. Protected routes take `Authorization: Bearer <access_token>`.

## Local demo authentication

```sh
curl -s http://localhost:8000/auth/dev-login \
  -H 'content-type: application/json' \
  -d '{"email":"alex@twonest.test"}'
```

The development token is the seeded member ID. It is deliberately not a production credential. `ENVIRONMENT=production` disables this login route; production authentication and signed/rotating sessions must be integrated before deployment.

## Member journey endpoints

| Capability | Method and path | Access rule |
|---|---|---|
| Current member/profile | `GET /me`, `GET /profiles/me` | Signed-in member |
| Update profile | `PUT /profiles/me` | Own profile |
| Onboarding profile and discovery preferences | `GET /onboarding`, `PATCH /onboarding`, `POST /onboarding/complete` | Own account; date of birth must be 18+; includes pause and temporary coarse travel area |
| Compatibility questions and saved answers | `GET /questionnaire`, `PUT /questionnaire/answers` | Own answers; private answers are not returned on profiles |
| Simulated verification | `POST /verifications/{kind}` | Own verification; local adapter |
| Limited introductions | `GET /introductions` | Own recommendations |
| Generate this week’s explainable recommendations | `POST /introductions/refresh` | Adult, complete member profile; three recommendations per rolling week |
| Interested/pass | `POST /introductions/{id}/decision` | Recommendation owner |
| Block/unblock member | `POST` / `DELETE /members/{id}/block` | Signed-in member; removes recommendations and closes an active conversation |
| Conversations/messages | `GET /conversations`, `POST /conversations/{id}/messages` | Active mutual match participants only |
| Unmatch | `POST /conversations/{id}/unmatch` | Conversation participant; closes messaging for both members |
| Experience catalogue/booking | `GET /experiences`, `POST /experiences/{id}/book` | Public catalogue; signed-in booking |
| Safety check | `POST /bookings/{id}/check-in`, `/check-out`, `/feedback` | Booking owner |
| Guided Circles | `GET /circles`, `POST /circles`, `POST /circles/{id}/join`, `/leave`, `GET /circles/{id}` | Signed-in member; detail/chat/media require active membership |
| Circle prompts | `POST /circles/{id}/responses`, `POST /circles/{id}/prompts/{prompt_id}/voice-note`, `GET /circles/{id}/voice-notes/{asset_key}` | Active Circle member; voice notes are capped at 10 MB and served only to group members |
| Circle chat | `POST /circles/{id}/messages` | Active Circle member |
| Circle meet-up | `POST /circles/{id}/meeting-plans`, `POST /circles/{id}/meeting-plans/{plan_id}/vote` | Active Circle member; plans open in week three |
| Couple invitation/acceptance | `POST /couples/invite`, `POST /couples/{id}/accept` | Inviter and invited account |
| Couple overview/Nest4 candidates | `GET /couples/me`, `GET /couples/{id}/nest4-candidates`, `GET /nest4` | Couple members only |
| TwoNest Together profile | `GET/PUT /couples/{id}/together`, `POST /couples/{id}/together/consent` | Active partners only; Nest4 discovery requires both current publication approvals |
| Couple dates/milestones | `GET/POST /couples/{id}/moments`, `PATCH /couples/{id}/moments/{moment_id}` | Active partners share date plans, activities and milestones |
| Home Mode consent/report | `POST /couples/{id}/home-mode`, `GET /couples/{id}/living-report` | Both members must consent for report; report uses the members’ shared, non-private home answers |
| Couple home preferences | `GET /couples/{id}/home-questionnaire`, `PUT /couples/{id}/home-questionnaire/answers` | Active couple members; each member can read and change only their own answers |
| Properties/viewing | `GET /properties`, `POST /couples/{id}/properties/{property_id}/shortlist`, `POST /couples/{id}/properties/{property_id}/viewings` | Active couple with both Home Mode consents |
| Moving checklist | `GET/POST /couples/{id}/moving-tasks`, `PATCH /couples/{id}/moving-tasks/{task_id}` | Active couple with both Home Mode consents; members share task completion and custom tasks |
| Experience waitlist | `GET /experiences`, `POST/DELETE /experiences/{id}/waitlist`, `GET /me/bookings`, `DELETE /bookings/{id}` | FIFO waitlist, private availability state, booking cancellation and automatic promotion |
| Nest4 introduction/decision | `POST /couples/{id}/nest4/{other_id}`, `POST /nest4/{match_id}/decision` | Exactly the four members; all four approve before meetup planning |
| Nest4 meetup | `POST /nest4/{id}/meeting-plans`, `POST /nest4/{id}/meeting-plans/{plan_id}/vote`, `/complete` | All four approve the proposal; each attendee votes; follow-up opens after the agreed meetup time |
| Nest4 private follow-up | `GET/POST /nest4/{id}/follow-up` | Each member sees and submits only their own choice; any “no connection” closes the match |
| Nest4 group chat | `GET/POST /nest4/{id}/messages` | Available only after the meetup and four positive follow-up choices |
| Safety report | `POST /safety/reports` with `subject_id`, `category` and `details` JSON | Signed-in reporter; report is private to safety staff |
| Partner booking operations | `GET /partner/bookings` | Restaurant partner sees own experiences only |
| Safety/admin operations | `GET /admin/operations`, `GET /admin/safety-reports` | Admin/moderator role |
| Account deletion | `DELETE /me` | Signed-in member |

## Notes on local persistence

SQLite is the default for a zero-credential local run. Set `DATABASE_URL` to the Compose PostGIS connection to use PostgreSQL. Alembic owns schema upgrades. The current schema covers the demonstrated journey; it does not yet implement every product entity in the project brief. The local verification provider only simulates statuses and accepts no government-ID files.

The onboarding resource contains the member’s date of birth, pronouns, gender and orientation, dating/friendship intentions, discovery radius, availability, languages, dietary/accessibility needs, event budget, discovery pause and optional travel area/end date. It is private to the authenticated member; the public introduction/profile response does not include these fields. Paused and hidden members are excluded from new recommendations. An active travel area temporarily replaces the member-selected broad area for approximate matching until its end date; the saved home area stays unchanged. The questionnaire definition is returned by the API in groups and supports single-select, multi-select, scale, free-text and ranked answers. Each saved answer carries an importance weight and privacy/deal-breaker choices. Recommendation refresh applies age, intention, mutual seeking, availability, visibility, recommendation-history and answer-deal-breaker filters before scoring; private answers are excluded from both scoring and hard filters. Without opted-in precise location, location scoring compares broad member-selected areas and does not claim a distance.

Circles use a four-week programme with a written introduction, a protected voice reflection, an actual multi-choice group poll and a group meet-up plan. Current-week responses, member-only text chat and meetup votes require active membership. Local voice files live in a temporary development media directory; production deployment must use the configured object-storage adapter and retention policy.

Home Mode answers are stored per couple and member. The questionnaire endpoint returns only the authenticated member’s own answers. The report requires both partners’ Home Mode consent, excludes every answer marked private, and returns counts and broad alignment/discussion categories without exposing either partner’s raw answers. A “Prefer to discuss privately” rent answer is always excluded.

### Guided onboarding and conversations

`PATCH /onboarding` persists `onboarding_step` (0–7), `preferred_age_min` and `preferred_age_max` alongside existing profile preferences. `POST /onboarding/complete` requires the adult profile, gender/seeking preferences, a short bio, at least three interests and at least three usable non-private compatibility answers. It returns the member with `profile.onboarding_completed = true`. Unfinished members are excluded from generated introductions. The client requests first introductions after successful completion.

Development signup returns 409 for an existing email; development login resumes an active existing account. Both development identity routes are disabled in production.

`GET /conversations/{id}` returns an active participant-only thread, including the other member ID for reporting. Closed or inaccessible threads return 404. Empty/whitespace-only messages are rejected. Unread state is currently local to the iOS device.

### Up for activity requests

All routes require an adult member with completed onboarding.

| Capability | Method and path | Behaviour |
|---|---|---|
| Browse requests | `GET /activities` | Open, unexpired, unblocked plans; optional `area`, `category`, `mode` filters |
| Own plans | `GET /activities/mine` | Hosted plans and pending/accepted memberships, including ended plans |
| Availability | `GET /activities/availability`, `PUT /activities/availability` | Activity categories, area, online/in-person/both mode and 15–240 minute availability |
| Create request | `POST /activities` | Category, title, description, mode, broad area, start time, private meeting details, discovery window and 1–5 companion places |
| Plan detail | `GET /activities/{id}` | Host-only pending applicants; accepted-member roster/chat; participant-only meeting details |
| Ask to join | `POST /activities/{id}/join` | Optional introduction note; creates a pending application |
| Accept/pass | `POST /activities/{id}/joins/{join_id}/decision` | Host only; `accepted` boolean; capacity enforced in a serialized transaction |
| Withdraw/leave | `POST /activities/{id}/leave` | Withdraws own membership and reopens a full plan when appropriate |
| End plan | `POST /activities/{id}/state` | Host only; `action` is `cancel` or `complete`; completion requires the start time to have passed |
| Plan chat | `POST /activities/{id}/messages` | Host and accepted members only, while the plan has at least one companion and is not cancelled/completed |

Categories are `shopping`, `hangout`, `drinks`, `gaming`, `coffee`, `food`, `fitness`, `culture`, `outdoors` and `other`. Creation mode is `in_person` or `online`. Start times can be within the next seven days; discovery closes after the selected 15–1440 minute window or one hour after the start, whichever comes first. A full plan declines outstanding pending applications. Existing accepted members may continue chat after discovery expires.

Broad-area filtering is case-insensitive equality, with online plans included when an area is selected. Available-member counts require matching categories, mode, area and an availability window covering the plan start; they exclude existing applicants, deleted accounts and blocked members. Availability does not automatically send an invitation or accept a plan. Private profile bios/interests are omitted from activity member cards. Existing member report and block endpoints also apply to activity participants.

The local client uses foreground polling. GPS matching, background dispatch and APNs delivery remain integrations.


### Rally map, invitations and live transport

The activity feature is now named **Rally** and is a standalone iOS navigation option with independent plan chat. Dating bios/preferences are excluded from activity member cards.

- `POST /activities` additionally accepts `latitude`, `longitude` and `meeting_name` for a public meetup venue. The server stores a separate rounded discovery point and exact meetup point. Cards return public `latitude`/`longitude`; `meeting_latitude`, `meeting_longitude` and `meeting_name` are host/accepted-member only. The iOS creation flow requires a selected meetup venue for in-person plans.
- `GET /activities?latitude=...&longitude=...&radius_km=...` uses geodesic radius search over rounded points, ignores the legacy broad-area filter when coordinates are supplied, sorts nearby requests first and includes online requests. Radius is 1–50 km. Existing plans without coordinates remain available through the broad-area list endpoint.
- `PUT /activities/availability` adds `show_on_map`, `latitude` and `longitude`. Coordinates are snapped to a fixed 0.005-degree grid before storage. Map presence requires explicit opt-in, enabled in-person/both availability and a location. Disabling presence clears its saved coordinates. Private member/device coordinates are not streamed.
- `GET /activities/nearby-members` requires search `latitude`/`longitude`, optional `radius_km` and `category`. It returns only active adult members with completed basic onboarding, unexpired opt-in availability, matching categories and no bilateral block. Coordinates and distance are approximate.
- `POST /activities/{id}/invite` takes `member_id`. Only a host with an open request can invite a visible, unblocked map member whose category/mode/start-time availability fits. In-person plans must be within 50 km of the member’s rounded point. Invitations appear in `/activities/mine` as `my_join_status = invited`.
- `POST /activities/{id}/join` accepts an invitation directly into an available place; otherwise it creates a pending host-reviewed request. Acceptance is capacity-serialized. Filling a plan declines other pending/invited memberships. `POST /activities/{id}/leave` also declines/withdraws an invitation.
- WebSocket `ws(s)://<backend>/activities/live` takes the same Bearer token in the Authorization header. `ready` and `refresh` events contain no personal data. Committed mutations publish refresh hints; 20-second ticks let clients remove expired presence. Clients re-fetch authorized resources. This is an in-process single-worker hub, not a background notification service.
- `POST /activities/{id}/transit` takes `origin_latitude`, `origin_longitude` and `transit_mode` (`all` or `bus`, a preference). Accepted members route to the exact venue; others route only to the coarse area. Server-only `GOOGLE_ROUTES_API_KEY` enables the Google Routes adapter. The response includes provider attribution, approximate-destination flag, time/distance, optional fare and itinerary steps. Missing credentials/routes/fares are explicitly represented; no fabricated transit or rideshare quote is returned. Origins are used for this request and not persisted by TwoNest.

Provider references: [Google transit routes and conditional fare availability](https://developers.google.com/maps/documentation/routes/transit-route), [Uber destination links](https://developer.uber.com/docs/riders/ride-requests/tutorials/deep-links/introduction), [MTA fares](https://www.mta.info/fares), [NJ TRANSIT tickets](https://www.njtransit.com/tickets-and-fares), [NYC taxi tariffs](https://www.nyc.gov/site/tlc/passengers/taxi-fare.page).
