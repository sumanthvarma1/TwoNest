"""Consent-based, expiring activity requests and participant-only plan chat."""
from datetime import date, datetime, timedelta, timezone
from uuid import uuid4
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, WebSocket
from sqlalchemy import select, func, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from .auth import current_user
from .db import get_db
from .models import User, Profile, OnboardingProfile, MemberBlock, ActivityAvailability, ActivityRequest, ActivityJoin, ActivityMessage
from .schemas import ActivityCreate, ActivityJoinInput, ActivityJoinDecision, ActivityStateInput, ActivityAvailabilityInput, ActivityMessageInput, ActivityInviteInput

from .activity_live import live_hub
from math import radians, sin, cos, asin, sqrt

router = APIRouter(prefix="/activities", tags=["Up for"])
CATEGORIES = {"shopping", "hangout", "drinks", "gaming", "coffee", "food", "fitness", "culture", "outdoors", "other"}


def coarse(value: float | None) -> float | None:
    return round(round(value / 0.005) * 0.005, 3) if value is not None else None


def km_between(lat1, lon1, lat2, lon2):
    a, b, c, d = map(radians, [lat1, lon1, lat2, lon2])
    return 6371 * 2 * asin(min(1, sqrt(sin((c-a)/2)**2 + cos(a)*cos(c)*sin((d-b)/2)**2)))


def utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def eligible_member(user: User = Depends(current_user), db: Session = Depends(get_db)) -> User:
    details = db.get(OnboardingProfile, user.id)
    profile = db.get(Profile, user.id)
    if user.role != "member": raise HTTPException(403, "Activity requests are for members")
    if not details or not details.onboarding_completed or not profile or not profile.complete:
        raise HTTPException(422, "Finish your member onboarding before making plans")
    try:
        born = date.fromisoformat(details.date_of_birth or "")
        today = date.today()
        age = today.year - born.year - ((today.month, today.day) < (born.month, born.day))
    except ValueError: age = 0
    if not 18 <= age <= 120: raise HTTPException(403, "Activity requests are for adult members")
    return user


def blocked(db: Session, left: str, right: str) -> bool:
    return db.scalar(select(MemberBlock.id).where(
        ((MemberBlock.blocker_id == left) & (MemberBlock.blocked_id == right)) |
        ((MemberBlock.blocker_id == right) & (MemberBlock.blocked_id == left))
    ).limit(1)) is not None


def accepted_ids(db: Session, request: ActivityRequest) -> list[str]:
    return list(db.scalars(select(ActivityJoin.member_id).join(User, User.id == ActivityJoin.member_id).where(
        ActivityJoin.request_id == request.id, ActivityJoin.status == "accepted", User.deleted_at.is_(None)
    )).all())


def visible_to(db: Session, request: ActivityRequest, user_id: str) -> bool:
    host = db.get(User, request.host_id)
    if not host or host.deleted_at: return False
    return not any(blocked(db, user_id, member_id) for member_id in [request.host_id] + accepted_ids(db, request) if member_id != user_id)


def effective_status(request: ActivityRequest, accepted: int) -> str:
    if request.status in {"cancelled", "completed"}: return request.status
    if accepted >= request.companion_limit: return "filled"
    return "expired" if utc(request.expires_at) <= datetime.now(timezone.utc) else "open"


def member_card(db: Session, user_id: str):
    user = db.get(User, user_id); availability = db.get(ActivityAvailability, user_id)
    # Rally shares account identity; dating bios and preferences do not enter this feature.
    return {"id": user_id, "first_name": user.first_name if user else "Former member", "area": availability.area if availability else "", "bio": "", "interests": availability.categories if availability else []}



def available_count(db: Session, request: ActivityRequest) -> int:
    rows = db.scalars(select(ActivityAvailability).join(User, User.id == ActivityAvailability.user_id).join(OnboardingProfile, OnboardingProfile.user_id == User.id).where(
        ActivityAvailability.expires_at > datetime.now(timezone.utc), ActivityAvailability.user_id != request.host_id,
        User.deleted_at.is_(None), OnboardingProfile.onboarding_completed == True
    )).all()
    known = set(db.scalars(select(ActivityJoin.member_id).where(ActivityJoin.request_id == request.id, ActivityJoin.status.in_(["pending", "accepted", "declined", "removed", "invited"]))).all())
    return sum(1 for row in rows if row.user_id not in known and utc(request.starts_at) <= utc(row.expires_at) and (not row.categories or request.category in row.categories)
        and row.mode in {"both", request.mode}
        and (request.mode == "online" or (km_between(row.latitude, row.longitude, request.latitude, request.longitude) <= 10 if row.latitude is not None and request.latitude is not None else row.area.strip().casefold() == request.area.strip().casefold()))
        and visible_to(db, request, row.user_id))


def card(db: Session, request: ActivityRequest, user_id: str, detail: bool = False):
    accepted = accepted_ids(db, request)
    mine = db.scalar(select(ActivityJoin).where(ActivityJoin.request_id == request.id, ActivityJoin.member_id == user_id))
    host = request.host_id == user_id
    member = host or bool(mine and mine.status == "accepted")
    status = effective_status(request, len(accepted))
    # An expired request closes discovery; accepted members can still coordinate their plan.
    chat_open = member and bool(accepted) and status not in {"cancelled", "completed"}
    result = {"id": request.id, "host": member_card(db, request.host_id), "category": request.category,
        "title": request.title, "description": request.description, "revision": request.revision, "mode": request.mode, "area": request.area,
        "starts_at": utc(request.starts_at).isoformat(), "expires_at": utc(request.expires_at).isoformat(),
        "companion_limit": request.companion_limit, "accepted_count": len(accepted), "status": status,
        "is_host": host, "my_join_status": ("expired" if mine.status in {"pending", "invited"} and status in {"expired", "cancelled", "completed"} else mine.status) if mine else None, "chat_open": chat_open,
        "pending_count": db.scalar(select(func.count()).select_from(ActivityJoin).where(ActivityJoin.request_id == request.id, ActivityJoin.status == "pending")) if host and status == "open" else 0,
        "available_members": available_count(db, request) if host and status == "open" else 0,
        "meeting_details": request.meeting_details if member else None,
        "latitude": request.latitude, "longitude": request.longitude,
        "meeting_latitude": request.meeting_latitude if member else None,
        "meeting_longitude": request.meeting_longitude if member else None,
        "meeting_name": request.meeting_name if member else None}
    if detail:
        joins = db.scalars(select(ActivityJoin).where(ActivityJoin.request_id == request.id).order_by(ActivityJoin.created_at)).all()
        result["participants"] = [member_card(db, request.host_id)] + [member_card(db, uid) for uid in accepted] if member else [member_card(db, request.host_id)]
        result["applicants"] = [{"id": row.id, "member": member_card(db, row.member_id), "note": row.note, "status": row.status} for row in joins if host and status == "open" and row.status == "pending" and not blocked(db, request.host_id, row.member_id) and db.get(User, row.member_id) and not db.get(User, row.member_id).deleted_at]
        result["messages"] = []
        if chat_open:
            messages = db.scalars(select(ActivityMessage).where(ActivityMessage.request_id == request.id).order_by(ActivityMessage.id.desc()).limit(100)).all()
            result["messages"] = [{"id": row.id, "sender_id": row.sender_id, "first_name": (db.get(User, row.sender_id).first_name if db.get(User, row.sender_id) else "Former member"), "body": row.body, "created_at": utc(row.created_at).isoformat()} for row in reversed(messages) if not blocked(db, user_id, row.sender_id)]
    return result


def get_request(db: Session, request_id: str, user_id: str, lock: bool = False) -> ActivityRequest:
    if lock:
        # Acquiring the request row's write lock serializes capacity changes on SQLite/Postgres.
        db.execute(update(ActivityRequest).where(ActivityRequest.id == request_id).values(revision=ActivityRequest.revision + 1))
    request = db.get(ActivityRequest, request_id)
    if not request or not visible_to(db, request, user_id): raise HTTPException(404, "Plan not found")
    if lock: db.refresh(request)
    return request


@router.get("/availability")
def get_availability(user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    row = db.get(ActivityAvailability, user.id)
    return {"enabled": bool(row and utc(row.expires_at) > datetime.now(timezone.utc)), "area": row.area if row else "New York",
        "categories": row.categories if row else [], "mode": row.mode if row else "both", "expires_at": utc(row.expires_at).isoformat() if row else None, "show_on_map": bool(row and row.show_on_map), "latitude": row.latitude if row else None, "longitude": row.longitude if row else None}


@router.put("/availability")
def set_availability(background_tasks: BackgroundTasks, payload: ActivityAvailabilityInput, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    if payload.mode not in {"both", "online", "in_person"} or any(category not in CATEGORIES for category in payload.categories):
        raise HTTPException(422, "Choose supported activities and a meeting mode")
    if payload.enabled and payload.mode != "online" and not payload.area.strip(): raise HTTPException(422, "Add your broad neighbourhood")
    row = db.get(ActivityAvailability, user.id) or ActivityAvailability(user_id=user.id)
    if (payload.latitude is None) != (payload.longitude is None): raise HTTPException(422, "Choose a valid location")
    if payload.enabled and payload.show_on_map and (payload.latitude is None or payload.mode == "online"):
        raise HTTPException(422, "Choose a map area and in-person availability to appear on the map")
    row.show_on_map = payload.show_on_map and payload.enabled
    row.latitude = coarse(payload.latitude) if row.show_on_map else None
    row.longitude = coarse(payload.longitude) if row.show_on_map else None
    row.area = payload.area.strip(); row.categories = list(dict.fromkeys(payload.categories)); row.mode = payload.mode
    row.expires_at = datetime.now(timezone.utc) + timedelta(minutes=payload.duration_minutes if payload.enabled else 0)
    db.add(row); db.commit(); background_tasks.add_task(live_hub.publish)
    return get_availability(user, db)


@router.get("/mine")
def my_requests(user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    joined = select(ActivityJoin.request_id).where(ActivityJoin.member_id == user.id, ActivityJoin.status.in_(["pending", "accepted", "invited"]))
    rows = db.scalars(select(ActivityRequest).where((ActivityRequest.host_id == user.id) | ActivityRequest.id.in_(joined)).order_by(ActivityRequest.created_at.desc()).limit(50)).all()
    return [card(db, row, user.id) for row in rows if visible_to(db, row, user.id)]


@router.get("")
def browse_requests(latitude: float | None = Query(default=None, ge=-85, le=85), longitude: float | None = Query(default=None, ge=-180, le=180), radius_km: float = Query(default=10, ge=1, le=50), area: str = Query(default="", max_length=100), category: str = Query(default="", max_length=32), mode: str = Query(default="both"), user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    if category and category not in CATEGORIES: raise HTTPException(422, "Choose a supported activity")
    if mode not in {"both", "online", "in_person"}: raise HTTPException(422, "Choose a meeting mode")
    query = select(ActivityRequest).where(ActivityRequest.status == "open", ActivityRequest.expires_at > datetime.now(timezone.utc), ActivityRequest.host_id != user.id)
    if category: query = query.where(ActivityRequest.category == category)
    if mode != "both": query = query.where(ActivityRequest.mode == mode)
    if (latitude is None) != (longitude is None): raise HTTPException(422, "Choose a valid search location")
    if latitude is not None:
        query = query.where((ActivityRequest.mode == "online") | ((ActivityRequest.latitude.between(latitude-radius_km/111-0.01, latitude+radius_km/111+0.01)) & ActivityRequest.longitude.is_not(None)))
    if latitude is None and area.strip(): query = query.where((ActivityRequest.mode == "online") | (func.lower(ActivityRequest.area) == area.strip().lower()))
    rows = db.scalars(query.order_by(ActivityRequest.starts_at).limit(500)).all()
    if latitude is not None:
        rows = [row for row in rows if row.mode == "online" or (row.latitude is not None and km_between(latitude, longitude, row.latitude, row.longitude) <= radius_km)]
        rows.sort(key=lambda row: km_between(latitude, longitude, row.latitude, row.longitude) if row.latitude is not None else float("inf"))
    rows = rows[:100]
    return [card(db, row, user.id) for row in rows if visible_to(db, row, user.id) and effective_status(row, len(accepted_ids(db, row))) == "open"]


@router.post("")
def create_request(background_tasks: BackgroundTasks, payload: ActivityCreate, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    if payload.category not in CATEGORIES or payload.mode not in {"in_person", "online"}: raise HTTPException(422, "Choose a supported activity and meeting mode")
    if len(payload.title.strip()) < 3: raise HTTPException(422, "Give your plan a short title")
    if payload.mode == "in_person" and len(payload.area.strip()) < 2: raise HTTPException(422, "Add a broad neighbourhood for your plan")
    try: starts = utc(datetime.fromisoformat(payload.starts_at.replace("Z", "+00:00")))
    except ValueError: raise HTTPException(422, "Choose a valid date and time")
    current = datetime.now(timezone.utc)
    if starts < current - timedelta(minutes=2) or starts > current + timedelta(days=7): raise HTTPException(422, "Choose a time now or within the next seven days")
    recent = db.scalar(select(func.count()).select_from(ActivityRequest).where(ActivityRequest.host_id == user.id, ActivityRequest.created_at > current - timedelta(hours=1))) or 0
    if recent >= 5: raise HTTPException(429, "You can post up to five plans per hour. Give your existing requests time to connect.")
    if (payload.latitude is None) != (payload.longitude is None): raise HTTPException(422, "Choose a valid meetup location")
    row = ActivityRequest(id=str(uuid4()), host_id=user.id, category=payload.category, title=payload.title.strip(), description=payload.description.strip(), mode=payload.mode,
        area=payload.area.strip() if payload.mode == "in_person" else "Online", meeting_details=payload.meeting_details.strip(), latitude=coarse(payload.latitude) if payload.mode == "in_person" else None, longitude=coarse(payload.longitude) if payload.mode == "in_person" else None, meeting_latitude=payload.latitude if payload.mode == "in_person" else None, meeting_longitude=payload.longitude if payload.mode == "in_person" else None, meeting_name=payload.meeting_name.strip() if payload.mode == "in_person" else "", starts_at=starts,
        expires_at=min(current + timedelta(minutes=payload.discovery_minutes), starts + timedelta(hours=1)), companion_limit=payload.companion_limit, status="open")
    db.add(row); db.commit(); background_tasks.add_task(live_hub.publish)
    return card(db, row, user.id, detail=True)



@router.websocket("/live")
async def live_activity(socket: WebSocket):
    await live_hub.connect(socket, eligible_member)


@router.get("/nearby-members")
def nearby_members(latitude: float = Query(ge=-85, le=85), longitude: float = Query(ge=-180, le=180), radius_km: float = Query(default=10, ge=1, le=50), category: str = "", user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    if category and category not in CATEGORIES: raise HTTPException(422, "Choose a supported activity")
    rows = db.scalars(select(ActivityAvailability).join(User, User.id == ActivityAvailability.user_id).join(OnboardingProfile, OnboardingProfile.user_id == User.id).join(Profile, Profile.user_id == User.id).where(
        ActivityAvailability.expires_at > datetime.now(timezone.utc), ActivityAvailability.show_on_map == True,
        ActivityAvailability.user_id != user.id, User.deleted_at.is_(None), OnboardingProfile.onboarding_completed == True,
        Profile.complete == True, ActivityAvailability.mode != "online",
        ActivityAvailability.latitude.between(latitude-radius_km/111-0.01, latitude+radius_km/111+0.01), ActivityAvailability.longitude.is_not(None)
    ).limit(500)).all()
    results = []
    for row in rows:
        distance = km_between(latitude, longitude, row.latitude, row.longitude)
        if distance > radius_km or blocked(db, user.id, row.user_id) or (category and row.categories and category not in row.categories): continue
        results.append({"id": row.user_id, "member": member_card(db, row.user_id), "latitude": row.latitude, "longitude": row.longitude, "categories": row.categories, "expires_at": utc(row.expires_at).isoformat(), "approx_distance_km": round(distance, 1)})
    return sorted(results, key=lambda row: row["approx_distance_km"])[:100]


@router.post("/{request_id}/invite")
def invite_member(request_id: str, payload: ActivityInviteInput, background_tasks: BackgroundTasks, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    request = get_request(db, request_id, user.id, lock=True)
    if request.host_id != user.id: raise HTTPException(403, "Only the host can invite someone")
    if effective_status(request, len(accepted_ids(db, request))) != "open": raise HTTPException(409, "This plan is no longer open")
    availability = db.get(ActivityAvailability, payload.member_id)
    candidate = db.get(User, payload.member_id)
    if not candidate or payload.member_id == user.id or not availability or not availability.show_on_map or utc(availability.expires_at) <= datetime.now(timezone.utc): raise HTTPException(409, "This member is no longer available on the map")
    eligible_member(candidate, db)
    if not visible_to(db, request, candidate.id): raise HTTPException(404, "Member is unavailable for this plan")
    if utc(request.starts_at) > utc(availability.expires_at) or (availability.categories and request.category not in availability.categories) or availability.mode not in {"both", request.mode}: raise HTTPException(409, "Choose a plan that fits this member’s availability")
    if request.mode == "in_person" and (request.latitude is None or availability.latitude is None or km_between(request.latitude, request.longitude, availability.latitude, availability.longitude) > 50): raise HTTPException(409, "Choose a plan within 50 km of this member")
    existing = db.scalar(select(ActivityJoin).where(ActivityJoin.request_id == request_id, ActivityJoin.member_id == candidate.id))
    if existing and existing.status != "withdrawn": raise HTTPException(409, "This member already has a request for this plan")
    total = db.scalar(select(func.count()).select_from(ActivityJoin).where(ActivityJoin.request_id == request_id, ActivityJoin.status.in_(["pending", "invited"]))) or 0
    if total >= 20: raise HTTPException(409, "This plan already has enough invitations and requests")
    invitation = existing or ActivityJoin(id=str(uuid4()), request_id=request_id, member_id=candidate.id)
    invitation.status = "invited"; invitation.note = ""; db.add(invitation)
    db.commit(); background_tasks.add_task(live_hub.publish)
    return card(db, request, user.id, detail=True)


@router.get("/{request_id}")
def request_detail(request_id: str, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    return card(db, get_request(db, request_id, user.id), user.id, detail=True)


@router.post("/{request_id}/join")
def join_request(background_tasks: BackgroundTasks, request_id: str, payload: ActivityJoinInput, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    request = get_request(db, request_id, user.id, lock=True)
    if request.host_id == user.id: raise HTTPException(422, "You already host this plan")
    mine = db.scalar(select(ActivityJoin).where(ActivityJoin.request_id == request_id, ActivityJoin.member_id == user.id))
    if mine and mine.status in {"pending", "accepted"}: return card(db, request, user.id, detail=True)
    if effective_status(request, len(accepted_ids(db, request))) != "open": raise HTTPException(409, "This plan is no longer looking for company")
    if mine and mine.status in {"declined", "removed"}: raise HTTPException(409, "This join request has ended")
    pending = db.scalar(select(func.count()).select_from(ActivityJoin).where(ActivityJoin.request_id == request_id, ActivityJoin.status == "pending")) or 0
    if pending >= 20 and not (mine and mine.status == "invited"): raise HTTPException(409, "This plan already has enough join requests to review")
    mine = mine or ActivityJoin(id=str(uuid4()), request_id=request_id, member_id=user.id)
    invited = bool(mine and mine.status == "invited")
    mine.note = payload.note.strip(); mine.status = "accepted" if invited else "pending"; db.add(mine)
    db.flush()
    if invited and len(accepted_ids(db, request)) >= request.companion_limit:
        request.status = "filled"
        db.execute(update(ActivityJoin).where(ActivityJoin.request_id == request.id, ActivityJoin.status.in_(["pending", "invited"])).values(status="declined"))
    try: db.commit(); background_tasks.add_task(live_hub.publish)
    except IntegrityError: db.rollback(); raise HTTPException(409, "Your join request is already saved. Refresh the plan.")
    return card(db, request, user.id, detail=True)


@router.post("/{request_id}/joins/{join_id}/decision")
def decide_join(background_tasks: BackgroundTasks, request_id: str, join_id: str, payload: ActivityJoinDecision, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    request = get_request(db, request_id, user.id, lock=True)
    if request.host_id != user.id: raise HTTPException(403, "Only the host can accept join requests")
    join = db.get(ActivityJoin, join_id)
    if not join or join.request_id != request_id: raise HTTPException(404, "Join request not found")
    if join.status == "accepted" and payload.accepted: return card(db, request, user.id, detail=True)
    if join.status != "pending": raise HTTPException(409, "This join request has already been decided")
    if effective_status(request, len(accepted_ids(db, request))) != "open": raise HTTPException(409, "This plan is no longer looking for company")
    candidate = db.get(User, join.member_id); details = db.get(OnboardingProfile, join.member_id)
    if not candidate or candidate.deleted_at or not details or not details.onboarding_completed or not visible_to(db, request, join.member_id): raise HTTPException(409, "This member is no longer available for this plan")
    join.status = "accepted" if payload.accepted else "declined"
    db.flush()
    if len(accepted_ids(db, request)) >= request.companion_limit:
        request.status = "filled"
        db.execute(update(ActivityJoin).where(ActivityJoin.request_id == request.id, ActivityJoin.status.in_(["pending", "invited"])).values(status="declined"))
    db.commit(); background_tasks.add_task(live_hub.publish)
    return card(db, request, user.id, detail=True)


@router.post("/{request_id}/leave")
def leave_request(background_tasks: BackgroundTasks, request_id: str, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    request = get_request(db, request_id, user.id, lock=True)
    if request.host_id == user.id: raise HTTPException(422, "Cancel the plan to stop hosting")
    mine = db.scalar(select(ActivityJoin).where(ActivityJoin.request_id == request_id, ActivityJoin.member_id == user.id))
    if not mine: raise HTTPException(404, "Join request not found")
    mine.status = "declined" if mine.status == "invited" else "withdrawn"
    if request.status == "filled": request.status = "open"
    db.commit(); background_tasks.add_task(live_hub.publish); return card(db, request, user.id, detail=True)


@router.post("/{request_id}/state")
def change_state(background_tasks: BackgroundTasks, request_id: str, payload: ActivityStateInput, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    request = get_request(db, request_id, user.id, lock=True)
    if request.host_id != user.id: raise HTTPException(403, "Only the host can change the plan")
    if payload.action not in {"cancel", "complete"}: raise HTTPException(422, "Choose cancel or complete")
    target = "cancelled" if payload.action == "cancel" else "completed"
    if request.status in {"cancelled", "completed"}:
        if request.status != target: raise HTTPException(409, "This plan has already ended")
    else:
        if target == "completed" and utc(request.starts_at) > datetime.now(timezone.utc): raise HTTPException(409, "Complete the plan after its start time")
        request.status = target
        db.execute(update(ActivityJoin).where(ActivityJoin.request_id == request.id, ActivityJoin.status.in_(["pending", "invited"])).values(status="declined"))
        db.commit(); background_tasks.add_task(live_hub.publish)
    return card(db, request, user.id, detail=True)


@router.post("/{request_id}/messages")
def send_activity_message(background_tasks: BackgroundTasks, request_id: str, payload: ActivityMessageInput, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    request = get_request(db, request_id, user.id, lock=True)
    if not card(db, request, user.id)["chat_open"]: raise HTTPException(403, "Plan chat opens for accepted members and closes when the plan ends")
    if not payload.body.strip(): raise HTTPException(422, "Write a message before sending")
    row = ActivityMessage(request_id=request_id, sender_id=user.id, body=payload.body.strip())
    db.add(row); db.commit(); background_tasks.add_task(live_hub.publish); db.refresh(row)
    return {"id": row.id, "sender_id": user.id, "first_name": user.first_name, "body": row.body, "created_at": utc(row.created_at).isoformat()}


def apply_activity_block(db: Session, blocker_id: str, subject_id: str):
    """Remove blocked membership before the existing block transaction commits."""
    related = select(ActivityJoin.request_id).where(ActivityJoin.member_id == blocker_id, ActivityJoin.status.in_(["pending", "accepted", "invited"]))
    requests = db.scalars(select(ActivityRequest).where(ActivityRequest.status.in_(["open", "filled"]), (ActivityRequest.host_id.in_([blocker_id, subject_id])) | ActivityRequest.id.in_(related))).all()
    for request in requests:
        db.execute(update(ActivityRequest).where(ActivityRequest.id == request.id).values(revision=ActivityRequest.revision + 1))
        db.refresh(request)
        joins = {join.member_id: join for join in db.scalars(select(ActivityJoin).where(ActivityJoin.request_id == request.id, ActivityJoin.status.in_(["pending", "accepted", "invited"]))).all()}
        removing = None
        if request.host_id == blocker_id: removing = joins.get(subject_id)
        elif request.host_id == subject_id or subject_id in joins: removing = joins.get(blocker_id)
        if removing:
            removing.status = "removed" if request.host_id == blocker_id else "withdrawn"
            if request.status == "filled": request.status = "open"
