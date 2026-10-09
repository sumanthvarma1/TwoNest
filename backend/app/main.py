"""TwoNest local-first API. Provider-backed identity, payments and notifications plug in behind these routes."""
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
import os
import re
import tempfile
from uuid import uuid4
from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from .db import Base, engine, get_db
from .auth import current_user
from .activity_live import live_hub
from .activities import router as activities_router, apply_activity_block
from .models import User, Profile, OnboardingProfile, CompatibilityAnswer, Verification, Introduction, Conversation, Message, Experience, Booking, ExperienceWaitlist, Couple, CoupleProfile, CoupleMoment, HomeModeAnswer, Nest4Decision, CoupleMatch, CoupleMatchDecision, Nest4MeetingPlan, Nest4MeetingVote, Nest4FollowupDecision, Nest4Message, SafetyReport, MemberBlock, Property, Shortlist, Viewing, MovingTask, Circle, CircleMember, CirclePrompt, CircleResponse, CircleMessage, CircleMeetingPlan, CircleMeetingVote
from .schemas import DevLogin, DevSignup, ProfileUpdate, OnboardingUpdate, CompatibilityAnswerBatch, HomeModeAnswerBatch, Nest4MeetingPlanCreate, Nest4MeetingVoteInput, Nest4FollowupInput, Nest4GroupMessageCreate, Decision, MessageCreate, VerificationUpdate, InvitePartner, Consent, CoupleProfileInput, CoupleMomentCreate, CoupleMomentUpdate, Feedback, ViewingCreate, MovingTaskCreate, MovingTaskUpdate, SafetyReportCreate, CircleCreate, CirclePromptResponseCreate, CircleMessageCreate, CircleMeetingPlanCreate, CircleMeetingVoteCreate
from .questionnaire import QUESTION_GROUPS, QUESTION_BY_ID
from .matching import Answer as ScoreAnswer, MemberSnapshot, score_match

DEMO_USERS = [
    ("member-alex", "alex@twonest.test", "Alex", "member"),
    ("member-sam", "sam@twonest.test", "Sam", "member"),
    ("member-jamie", "jamie@twonest.test", "Jamie", "member"),
    ("member-riley", "riley@twonest.test", "Riley", "member"),
    ("partner-one", "partner@twonest.test", "NestTable Partner", "restaurant_partner"),
    ("housing-one", "homes@twonest.test", "TwoNest Homes Partner", "apartment_partner"),
    ("host-one", "host@twonest.test", "Experience Host", "event_host"),
    ("moderator-one", "moderator@twonest.test", "TwoNest Moderator", "moderator"),
    ("support-one", "support@twonest.test", "TwoNest Support", "customer_support"),
    ("admin-one", "admin@twonest.test", "TwoNest Admin", "administrator"),
]

DEMO_COMPATIBILITY_ANSWERS = {
    "relationship_timeline": "Within 1–2 years", "marriage": "Open to it", "children": "Open to either",
    "family_involvement": 4, "religion_and_spirituality": "Not a major part", "culture_and_tradition": 3,
    "career_and_ambition": "Important but balanced", "spending_and_saving": "Balance saving and enjoying",
    "communication_style": "Talk it through right away", "conflict_style": "Calm direct conversation", "social_energy": 3,
    "weekend_interests": ["Cooking", "Museums and culture", "Quiet weekends", "Trying new restaurants"],
    "travel_style": "A mix of everything", "food_and_drink": "A mix", "fitness": "A few times a week",
    "smoking": "Never", "alcohol": "Socially", "pets": "Happy to live with pets",
    "sleep_schedule": "Somewhere in between", "cleanliness": 4, "cooking_at_home": "A few times a week",
    "working_from_home": "A few days a week", "guests_at_home": 3, "personal_space": 3,
    "neighbourhood_preferences": ["Parks", "Cafes", "Public transport", "Restaurants"],
    "rent_budget": "£1,500–£2,000", "moving_timeline": "Only when it feels right",
}

@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    from .db import SessionLocal
    with SessionLocal() as db:
        for uid, email, name, role in DEMO_USERS:
            if not db.get(User, uid):
                db.add(User(id=uid, email=email, first_name=name, role=role))
                db.add(Profile(user_id=uid, intention="serious_dating", bio=f"{name} enjoys good food, thoughtful conversation and exploring London.", area="East London", interests="cooking,quiet weekends,travel", complete=True))
            if role == "member" and not db.get(OnboardingProfile, uid):
                db.add(OnboardingProfile(user_id=uid, date_of_birth="1992-04-15", onboarding_completed=True, pronouns="", gender_identity="man" if uid in {"member-alex", "member-jamie"} else "woman", sexual_orientation="", dating_preferences=["any"], friendship_intention="", search_radius_km=40, languages=["English"], availability=["weekends"], dietary_requirements=[], accessibility_needs=[], event_budget_min=0, event_budget_max=100))
            if role == "member":
                details = db.get(OnboardingProfile, uid)
                if details:
                    details.onboarding_completed = True
                    if not details.gender_identity: details.gender_identity = "man" if uid in {"member-alex", "member-jamie"} else "woman"
                    if not details.dating_preferences: details.dating_preferences = ["any"]
                for question_id, value in DEMO_COMPATIBILITY_ANSWERS.items():
                    exists = db.scalar(select(CompatibilityAnswer).where(CompatibilityAnswer.user_id == uid, CompatibilityAnswer.question_id == question_id))
                    if not exists:
                        db.add(CompatibilityAnswer(user_id=uid, question_id=question_id, category=QUESTION_BY_ID[question_id]["category"], value=value, importance=2, deal_breaker=False, is_private=False))
        if not db.get(Introduction, "intro-alex-sam"):
            db.add(Introduction(id="intro-alex-sam", user_id="member-alex", candidate_id="member-sam", score=88, label="Strong Alignment", reasons="You both want a long-term relationship, enjoy cooking, prefer quieter weekends and are considering living in East London."))
            db.add(Introduction(id="intro-sam-alex", user_id="member-sam", candidate_id="member-alex", score=88, label="Strong Alignment", reasons="You both want a long-term relationship, enjoy cooking, prefer quieter weekends and are considering living in East London."))
        if not db.get(Experience, "dinner-east-london"):
            db.add(Experience(id="dinner-east-london", title="A Table for Two", format="curated_date", venue="The Evergreen Kitchen", area="East London", starts_at="2026-10-16T19:00:00+01:00", capacity=16, partner_id="partner-one"))
            db.add(Experience(id="experience-circles", title="New-to-the-city supper club", format="singles_table_six", venue="The Evergreen Kitchen", area="East London", starts_at="2026-10-18T18:30:00+01:00", capacity=18, partner_id="partner-one"))
        if not db.get(Circle, "circle-east-london"):
            started_at = (datetime.now(timezone.utc) - timedelta(days=15)).isoformat()
            db.add(Circle(id="circle-east-london", title="New to East London", theme="new_to_city", area="East London", started_at=started_at, created_by="member-sam", max_members=8))
            db.flush()
            for week, title, kind, body, options in [
                (1, "A small introduction", "written", "What brought you to this neighbourhood, and what would make it feel like home?", []),
                (2, "Let your voice in", "voice", "Share a place, a song or a small ritual that makes a new city feel less unfamiliar.", []),
                (3, "Choose a first get-together", "poll", "What kind of low-pressure group outing would you enjoy together?", ["Coffee and a walk", "Shared dinner", "Museum or gallery", "Board games"]),
                (4, "Meet in the neighbourhood", "meetup", "Pick a welcoming local place and make a plan to meet as a group.", []),
            ]:
                db.add(CirclePrompt(id=f"circle-east-london-week-{week}", circle_id="circle-east-london", week=week, title=title, prompt_type=kind, body=body, options=options))
        if db.get(Circle, "circle-east-london"):
            for member_id in ("member-sam", "member-jamie", "member-riley"):
                if not db.scalar(select(CircleMember.id).where(CircleMember.circle_id == "circle-east-london", CircleMember.member_id == member_id)):
                    db.add(CircleMember(circle_id="circle-east-london", member_id=member_id))
            poll = db.get(CirclePrompt, "circle-east-london-week-3")
            if poll and not poll.options: poll.options = ["Coffee and a walk", "Shared dinner", "Museum or gallery", "Board games"]
        if not db.get(Property, "flat-hackney"):
            db.add(Property(id="flat-hackney", title="Bright two-bedroom near London Fields", area="Hackney", rent_pcm=2450, bedrooms=2, partner_id="partner-one"))
            db.add(Property(id="flat-bow", title="Quiet two-bedroom with a work nook", area="Bow", rent_pcm=2200, bedrooms=2, partner_id="partner-one"))
        db.commit()
    yield

app = FastAPI(title="TwoNest API", version="0.1.0", description="Local demo API for considerate introductions, experiences and shared home planning.", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["http://localhost:3000", "http://localhost:3001", "http://localhost:3002"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

from . import activity_travel  # Registers provider-backed transit routes on the activity router.
app.include_router(activities_router)

@app.get("/health")
def health(): return {"status": "ok", "service": "twonest-api"}

def require_roles(*roles):
    def check(user: User = Depends(current_user)):
        if user.role not in roles: raise HTTPException(403, "This account cannot access this operation")
        return user
    return check

def require_circle_member(db: Session, circle_id: str, user_id: str) -> Circle:
    circle = db.get(Circle, circle_id)
    membership = db.scalar(select(CircleMember.id).where(CircleMember.circle_id == circle_id, CircleMember.member_id == user_id, CircleMember.status == "active"))
    if not circle or not membership:
        raise HTTPException(404, "Circle not found")
    return circle

def circle_week(circle: Circle) -> int:
    try:
        started = datetime.fromisoformat(circle.started_at.replace("Z", "+00:00"))
    except ValueError:
        return 1
    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)
    elapsed = max(0, (datetime.now(timezone.utc) - started.astimezone(timezone.utc)).days)
    return min(4, elapsed // 7 + 1)

def circle_program_finished(circle: Circle) -> bool:
    try:
        started = datetime.fromisoformat(circle.started_at.replace("Z", "+00:00"))
    except ValueError:
        return False
    if started.tzinfo is None: started = started.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - started.astimezone(timezone.utc)).days >= 28

def circle_card(db: Session, circle: Circle, user_id: str):
    count = db.scalar(select(func.count()).select_from(CircleMember).where(CircleMember.circle_id == circle.id, CircleMember.status == "active")) or 0
    joined = db.scalar(select(CircleMember.id).where(CircleMember.circle_id == circle.id, CircleMember.member_id == user_id, CircleMember.status == "active")) is not None
    return {"id": circle.id, "title": circle.title, "theme": circle.theme, "area": circle.area, "starts_at": circle.started_at, "week": circle_week(circle), "member_count": count, "max_members": circle.max_members, "joined": joined, "status": circle.status}

def public_user(db: Session, uid: str):
    user = db.get(User, uid); profile = db.get(Profile, uid)
    if not user or not profile: raise HTTPException(404, "Member not found")
    complete = profile.complete
    if user.role == "member":
        details = db.get(OnboardingProfile, user.id)
        complete = bool(complete and details and details.date_of_birth)
    return {"id": user.id, "first_name": user.first_name, "role": user.role, "profile": {"intention": profile.intention, "bio": profile.bio, "area": profile.area, "interests": profile.interests.split(","), "complete": complete, "onboarding_completed": bool(user.role != "member" or (details and details.onboarding_completed))}}

@app.post("/auth/dev-login")
def dev_login(payload: DevLogin, db: Session = Depends(get_db)):
    if __import__("os").getenv("ENVIRONMENT", "development") == "production": raise HTTPException(404, "Not found")
    user = db.scalar(select(User).where(User.email == payload.email.strip().lower()))
    if not user or user.deleted_at: raise HTTPException(401, "No active account found for this email. Create an account to begin.")
    return {"access_token": user.id, "token_type": "bearer", "user": public_user(db, user.id)}

@app.post("/auth/dev-signup")
def dev_signup(payload: DevSignup, db: Session = Depends(get_db)):
    if os.getenv("ENVIRONMENT", "development") == "production": raise HTTPException(404, "Not found")
    email = payload.email.strip().lower()
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email): raise HTTPException(422, "Enter a valid email address")
    user = db.scalar(select(User).where(User.email == email))
    if user: raise HTTPException(409, "An account already exists for this email. Please log in.")
    if not user:
        user = User(id=str(uuid4()), email=email, first_name="You", role="member")
        db.add(user)
        db.add(Profile(user_id=user.id, intention="serious_dating", bio="", area="", interests="", complete=False, visibility="matches"))
        db.commit()
    return {"access_token": user.id, "token_type": "bearer", "user": public_user(db, user.id)}

@app.delete("/me")
def delete_account(background_tasks: BackgroundTasks, user: User = Depends(current_user), db: Session = Depends(get_db)):
    from datetime import datetime, timezone
    user.deleted_at = datetime.now(timezone.utc); db.commit(); background_tasks.add_task(live_hub.publish)
    return {"deleted": True}

@app.get("/me")
def me(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return public_user(db, user.id)

@app.get("/profiles/me")
def get_profile(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return public_user(db, user.id)["profile"]

def onboarding_payload(user: User, db: Session):
    profile = db.get(Profile, user.id) or Profile(user_id=user.id)
    details = db.get(OnboardingProfile, user.id) or OnboardingProfile(
        user_id=user.id, pronouns="", gender_identity="", sexual_orientation="",
        dating_preferences=[], friendship_intention="", search_radius_km=40,
        languages=[], availability=[], dietary_requirements=[], accessibility_needs=[],
        event_budget_min=0, event_budget_max=100, discovery_paused=False,
        travel_mode_area="", travel_mode_until=None,
    )
    return {
        "first_name": user.first_name, "date_of_birth": details.date_of_birth,
        "pronouns": details.pronouns, "gender_identity": details.gender_identity,
        "sexual_orientation": details.sexual_orientation, "dating_preferences": details.dating_preferences or [],
        "intention": profile.intention, "friendship_intention": details.friendship_intention,
        "area": profile.area, "search_radius_km": details.search_radius_km,
        "preferred_age_min": details.preferred_age_min if details.preferred_age_min is not None else 18,
        "preferred_age_max": details.preferred_age_max if details.preferred_age_max is not None else 80,
        "onboarding_step": details.onboarding_step or 0,
        "languages": details.languages or [], "availability": details.availability or [],
        "dietary_requirements": details.dietary_requirements or [],
        "accessibility_needs": details.accessibility_needs or [],
        "event_budget_min": details.event_budget_min, "event_budget_max": details.event_budget_max,
        "discovery_paused": details.discovery_paused,
        "travel_mode_area": details.travel_mode_area,
        "travel_mode_until": details.travel_mode_until,
        "bio": profile.bio, "interests": profile.interests.split(",") if profile.interests else [],
        "visibility": profile.visibility, "complete": bool(profile.complete and details.date_of_birth),
    }

@app.get("/onboarding")
def get_onboarding(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return onboarding_payload(user, db)

@app.patch("/onboarding")
def update_onboarding(payload: OnboardingUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    values = payload.model_dump(exclude_unset=True)
    if "date_of_birth" in values:
        from datetime import date
        try: birthday = date.fromisoformat(values["date_of_birth"])
        except (TypeError, ValueError): raise HTTPException(422, "Date of birth must use YYYY-MM-DD")
        today = date.today()
        age = today.year - birthday.year - ((today.month, today.day) < (birthday.month, birthday.day))
        if birthday > today or not 18 <= age <= 120: raise HTTPException(422, "Enter a valid date of birth for an adult aged 18–120")
    if "travel_mode_until" in values and values["travel_mode_until"]:
        try: travel_until = date.fromisoformat(values["travel_mode_until"])
        except (TypeError, ValueError): raise HTTPException(422, "Travel mode end date must use YYYY-MM-DD")
        if travel_until < date.today(): raise HTTPException(422, "Travel mode end date must be today or later")
    if values.get("travel_mode_area") is not None:
        values["travel_mode_area"] = values["travel_mode_area"].strip()
    if values.get("travel_mode_area") == "":
        values["travel_mode_until"] = None
    profile = db.get(Profile, user.id) or Profile(user_id=user.id)
    details = db.get(OnboardingProfile, user.id) or OnboardingProfile(
        user_id=user.id, pronouns="", gender_identity="", sexual_orientation="",
        dating_preferences=[], friendship_intention="", search_radius_km=40,
        languages=[], availability=[], dietary_requirements=[], accessibility_needs=[],
        event_budget_min=0, event_budget_max=100, discovery_paused=False,
        travel_mode_area="", travel_mode_until=None,
    )
    if any(value is None for key, value in values.items() if key != "travel_mode_until"):
        raise HTTPException(422, "Profile fields cannot be null")
    minimum = values.get("preferred_age_min", details.preferred_age_min if details.preferred_age_min is not None else 18)
    maximum = values.get("preferred_age_max", details.preferred_age_max if details.preferred_age_max is not None else 80)
    if minimum > maximum: raise HTTPException(422, "Minimum partner age cannot exceed the maximum")
    if "dating_preferences" in values and any(value not in {"man", "woman", "non binary", "any"} for value in values["dating_preferences"]):
        raise HTTPException(422, "Choose supported partner preferences")
    if "first_name" in values:
        first_name = values.pop("first_name").strip()
        if not first_name: raise HTTPException(422, "First name cannot be empty")
        user.first_name = first_name
    if "intention" in values: profile.intention = values.pop("intention")
    if "area" in values: profile.area = values.pop("area")
    if "bio" in values: profile.bio = values.pop("bio")
    if "interests" in values: profile.interests = ",".join(values.pop("interests"))
    if "visibility" in values: profile.visibility = values.pop("visibility")
    for key, value in values.items(): setattr(details, key, value)
    if details.event_budget_min > details.event_budget_max:
        raise HTTPException(422, "Minimum event budget cannot exceed the maximum")
    profile.complete = bool(user.first_name and details.date_of_birth and profile.area and profile.intention)
    db.add(profile); db.add(details); db.commit(); db.refresh(user); db.refresh(profile); db.refresh(details)
    return onboarding_payload(user, db)

@app.post("/onboarding/complete")
def complete_onboarding(user: User = Depends(current_user), db: Session = Depends(get_db)):
    profile = db.get(Profile, user.id)
    details = db.get(OnboardingProfile, user.id)
    if not profile or not details or not profile.complete or not details.date_of_birth:
        raise HTTPException(422, "Add your name, date of birth and neighbourhood first")
    if not details.gender_identity or not details.dating_preferences:
        raise HTTPException(422, "Tell us about yourself and who you would like to meet")
    if len(profile.bio.strip()) < 10 or len([item for item in profile.interests.split(",") if item.strip()]) < 3:
        raise HTTPException(422, "Add a short introduction and at least three interests")
    answers = db.scalars(select(CompatibilityAnswer).where(CompatibilityAnswer.user_id == user.id, CompatibilityAnswer.is_private == False)).all()
    if sum(1 for answer in answers if answer.question_id in QUESTION_BY_ID and answer.value not in (None, "", [])) < 3:
        raise HTTPException(422, "Choose at least three compatibility answers to use for matching")
    details.onboarding_completed = True
    details.onboarding_step = 7
    db.commit()
    return public_user(db, user.id)

@app.put("/profiles/me")
def update_profile(payload: ProfileUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    p = db.get(Profile, user.id) or Profile(user_id=user.id); p.intention=payload.intention; p.bio=payload.bio; p.area=payload.area; p.interests=",".join(payload.interests); p.complete=payload.complete; p.visibility=payload.visibility
    db.add(p); db.commit(); return public_user(db, user.id)["profile"]

def _questionnaire_answer_is_valid(question, value) -> bool:
    kind = question["response_type"]
    if kind == "single_select":
        return isinstance(value, str) and value in question["options"]
    if kind in {"multiple_select", "ranking"}:
        return isinstance(value, list) and all(isinstance(item, str) and item in question["options"] for item in value) and len(value) == len(set(value)) and (kind != "ranking" or len(value) <= len(question["options"]))
    if kind == "scale":
        return isinstance(value, int) and not isinstance(value, bool) and question["minimum"] <= value <= question["maximum"]
    if kind == "free_text":
        return isinstance(value, str) and len(value) <= question.get("maximum_length", 500)
    return False

@app.get("/questionnaire")
def get_questionnaire(user: User = Depends(current_user), db: Session = Depends(get_db)):
    answers = db.scalars(select(CompatibilityAnswer).where(CompatibilityAnswer.user_id == user.id)).all()
    return {
        "groups": QUESTION_GROUPS,
        "answers": [{"question_id": row.question_id, "value": row.value, "importance": row.importance, "deal_breaker": row.deal_breaker, "is_private": row.is_private} for row in answers],
    }

@app.put("/questionnaire/answers")
def save_questionnaire_answers(payload: CompatibilityAnswerBatch, user: User = Depends(current_user), db: Session = Depends(get_db)):
    for item in payload.answers:
        question = QUESTION_BY_ID.get(item.question_id)
        if not question: raise HTTPException(422, f"Unknown questionnaire item: {item.question_id}")
        if not _questionnaire_answer_is_valid(question, item.value): raise HTTPException(422, f"Invalid answer for {item.question_id}")
    saved = []
    for item in payload.answers:
        question = QUESTION_BY_ID[item.question_id]
        row = db.scalar(select(CompatibilityAnswer).where(CompatibilityAnswer.user_id == user.id, CompatibilityAnswer.question_id == item.question_id))
        if row is None: row = CompatibilityAnswer(user_id=user.id, question_id=item.question_id, category=question["category"], value=item.value)
        row.category = question["category"]; row.value = item.value; row.importance = item.importance
        row.deal_breaker = item.deal_breaker; row.is_private = item.is_private
        db.add(row); saved.append(row)
    db.commit()
    return {"saved": len(saved), "answer_count": db.scalar(select(func.count()).select_from(CompatibilityAnswer).where(CompatibilityAnswer.user_id == user.id))}

@app.post("/verifications/{kind}")
def verify(kind: str, payload: VerificationUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if kind not in {"email", "phone", "selfie_liveness", "government_id", "employment", "education"}: raise HTTPException(422, "Unknown verification type")
    if payload.status not in {"pending", "approved", "rejected"}: raise HTTPException(422, "Invalid verification status")
    row = db.scalar(select(Verification).where(Verification.user_id==user.id, Verification.kind==kind)) or Verification(user_id=user.id, kind=kind)
    row.status=payload.status; db.add(row); db.commit(); return {"kind": kind, "status": row.status, "provider": "local-development"}

def _member_snapshot(db: Session, user: User) -> MemberSnapshot | None:
    profile = db.get(Profile, user.id)
    details = db.get(OnboardingProfile, user.id)
    if not profile or not details or not details.date_of_birth: return None
    try: birthday = date.fromisoformat(details.date_of_birth)
    except ValueError: return None
    today = date.today()
    age = today.year - birthday.year - ((today.month, today.day) < (birthday.month, birthday.day))
    answer_rows = db.scalars(select(CompatibilityAnswer).where(CompatibilityAnswer.user_id == user.id)).all()
    answers: dict[str, dict[str, ScoreAnswer]] = {}
    for row in answer_rows:
        answers.setdefault(row.category, {})[row.question_id] = ScoreAnswer(row.value, float(row.importance), row.deal_breaker, row.is_private)
    history = db.scalars(select(Introduction).where((Introduction.user_id == user.id) | (Introduction.candidate_id == user.id))).all()
    history_ids = {row.candidate_id if row.user_id == user.id else row.user_id for row in history}
    blocked_ids = set(db.scalars(select(MemberBlock.blocked_id).where(MemberBlock.blocker_id == user.id)).all())
    approved = db.scalar(select(Verification.id).where(Verification.user_id == user.id, Verification.status == "approved").limit(1)) is not None
    completeness = min(1.0, (3 + min(len(answer_rows), 20) / 20 * 7) / 10)
    return MemberSnapshot(
        member_id=user.id, age=age, intention=profile.intention,
        seeking=set(details.dating_preferences or []), latitude=None, longitude=None,
        gender_identity=details.gender_identity,
        preferred_age_min=details.preferred_age_min, preferred_age_max=details.preferred_age_max,
        area=(details.travel_mode_area if details.travel_mode_area and details.travel_mode_until and details.travel_mode_until >= date.today().isoformat() else profile.area),
        search_radius_km=details.search_radius_km,
        availability=set(details.availability or []), answers=answers,
        interests={value.strip().casefold() for value in profile.interests.split(",") if value.strip()},
        history_ids=history_ids, blocked_ids=blocked_ids,
        active=user.deleted_at is None and details.onboarding_completed and profile.complete and profile.visibility != "private" and not details.discovery_paused,
        verified=approved, profile_completeness=completeness,
    )

def _recent_recommendation_count(db: Session, user_id: str) -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    rows = db.scalars(select(Introduction).where(Introduction.user_id == user_id)).all()
    return sum(1 for row in rows if row.created_at and (row.created_at.replace(tzinfo=timezone.utc) if row.created_at.tzinfo is None else row.created_at) >= cutoff)

@app.get("/introductions")
def introductions(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(Introduction).where(Introduction.user_id==user.id, Introduction.status!="passed").order_by(Introduction.score.desc())).all()
    outgoing = set(db.scalars(select(MemberBlock.blocked_id).where(MemberBlock.blocker_id == user.id)).all())
    incoming = set(db.scalars(select(MemberBlock.blocker_id).where(MemberBlock.blocked_id == user.id)).all())
    hidden = outgoing | incoming
    return [{"id":r.id,"score":r.score,"label":r.label,"reasons":r.reasons,"status":r.status,"candidate":public_user(db,r.candidate_id)} for r in rows if r.candidate_id not in hidden]

@app.post("/introductions/refresh")
def refresh_introductions(user: User = Depends(current_user), db: Session = Depends(get_db)):
    if user.role != "member": raise HTTPException(403, "Member introductions only")
    discovery = db.get(OnboardingProfile, user.id)
    if discovery and discovery.discovery_paused: raise HTTPException(409, "Discovery is paused. Resume it in your profile settings to request introductions.")
    member = _member_snapshot(db, user)
    if member is None or not member.active: raise HTTPException(422, "Complete your adult member profile before requesting introductions")
    visible_answers = sum(1 for group in member.answers.values() for answer in group.values() if not answer.private)
    if visible_answers < 3: raise HTTPException(422, "Answer at least three compatibility questions first")
    slots = max(0, 3 - _recent_recommendation_count(db, user.id))
    if slots == 0: return {"created_count": 0, "remaining_this_week": 0}
    candidates = []
    for candidate in db.scalars(select(User).where(User.role == "member", User.id != user.id, User.deleted_at.is_(None))).all():
        snapshot = _member_snapshot(db, candidate)
        if snapshot is None or _recent_recommendation_count(db, candidate.id) >= 3: continue
        result = score_match(member, snapshot)
        if result.eligible: candidates.append((result, candidate, snapshot))
    candidates.sort(key=lambda row: (row[0].score, row[0].label), reverse=True)
    created = 0
    for result, candidate, snapshot in candidates[:slots]:
        reverse = score_match(snapshot, member)
        if not reverse.eligible: continue
        reason_text = "; ".join(result.reasons)
        db.add(Introduction(id=str(uuid4()), user_id=user.id, candidate_id=candidate.id, score=result.score, label=result.label, reasons=reason_text, status="pending"))
        db.add(Introduction(id=str(uuid4()), user_id=candidate.id, candidate_id=user.id, score=reverse.score, label=reverse.label, reasons="; ".join(reverse.reasons), status="pending"))
        created += 1
    db.commit()
    return {"created_count": created, "remaining_this_week": max(0, slots - created)}

@app.post("/introductions/{intro_id}/decision")
def decide(intro_id: str, payload: Decision, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if payload.decision not in {"interested", "passed"}: raise HTTPException(422, "Decision must be interested or passed")
    row=db.get(Introduction,intro_id)
    if not row or row.user_id != user.id: raise HTTPException(404,"Introduction not found")
    if db.scalar(select(MemberBlock.id).where(((MemberBlock.blocker_id == user.id) & (MemberBlock.blocked_id == row.candidate_id)) | ((MemberBlock.blocker_id == row.candidate_id) & (MemberBlock.blocked_id == user.id))).limit(1)):
        raise HTTPException(404, "Introduction not found")
    row.status=payload.decision; db.commit()
    mutual=False; conversation=None
    if payload.decision=="interested":
        reverse=db.scalar(select(Introduction).where(Introduction.user_id==row.candidate_id,Introduction.candidate_id==user.id))
        if reverse and reverse.status=="interested":
            mutual=True
            conversation=db.scalar(select(Conversation).where(Conversation.user_a.in_([user.id,row.candidate_id]),Conversation.user_b.in_([user.id,row.candidate_id])))
            if not conversation:
                conversation=Conversation(id=str(uuid4()),user_a=user.id,user_b=row.candidate_id); db.add(conversation); db.commit()
    return {"decision":payload.decision,"mutual":mutual,"conversation_id":conversation.id if conversation else None}

@app.post("/members/{subject_id}/block")
def block_member(subject_id: str, background_tasks: BackgroundTasks, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if subject_id == user.id: raise HTTPException(422, "You cannot block your own account")
    subject = db.get(User, subject_id)
    if not subject or subject.role != "member" or subject.deleted_at: raise HTTPException(404, "Member not found")
    row = db.scalar(select(MemberBlock).where(MemberBlock.blocker_id == user.id, MemberBlock.blocked_id == subject_id))
    if row is None: db.add(MemberBlock(blocker_id=user.id, blocked_id=subject_id))
    own_introductions = db.scalars(select(Introduction).where(Introduction.user_id == user.id, Introduction.candidate_id == subject_id)).all()
    for introduction in own_introductions: introduction.status = "passed"
    conversations = db.scalars(select(Conversation).where(((Conversation.user_a == user.id) & (Conversation.user_b == subject_id)) | ((Conversation.user_a == subject_id) & (Conversation.user_b == user.id)))).all()
    for conversation in conversations: conversation.active = False
    apply_activity_block(db, user.id, subject_id)
    db.commit(); background_tasks.add_task(live_hub.publish)
    return {"blocked": True}

@app.delete("/members/{subject_id}/block")
def unblock_member(subject_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = db.scalar(select(MemberBlock).where(MemberBlock.blocker_id == user.id, MemberBlock.blocked_id == subject_id))
    if row: db.delete(row); db.commit()
    return {"blocked": False}

def conversation_payload(db: Session, conversation: Conversation, user_id: str):
    other_id = conversation.user_b if conversation.user_a == user_id else conversation.user_a
    messages = db.scalars(select(Message).where(Message.conversation_id == conversation.id).order_by(Message.created_at, Message.id)).all()
    return {"id": conversation.id, "member_id": other_id, "with": public_user(db, other_id)["first_name"], "messages": [{"id": m.id, "sender_id": m.sender_id, "body": m.body, "created_at": m.created_at.isoformat()} for m in messages]}

@app.get("/conversations")
def conversations(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(Conversation).where((Conversation.user_a == user.id) | (Conversation.user_b == user.id), Conversation.active == True)).all()
    return [conversation_payload(db, row, user.id) for row in rows]

@app.get("/conversations/{conversation_id}")
def get_conversation(conversation_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = db.get(Conversation, conversation_id)
    if not row or user.id not in (row.user_a, row.user_b) or not row.active:
        raise HTTPException(404, "This conversation has ended or is no longer available")
    return conversation_payload(db, row, user.id)

@app.post("/conversations/{conversation_id}/unmatch")
def unmatch(conversation_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    conversation = db.get(Conversation, conversation_id)
    if not conversation or user.id not in (conversation.user_a, conversation.user_b): raise HTTPException(404, "Conversation not found")
    conversation.active = False; db.commit()
    return {"unmatched": True}

@app.get("/circles")
def list_circles(user: User = Depends(current_user), db: Session = Depends(get_db)):
    if user.role != "member": raise HTTPException(403, "Circles are for members")
    circles = db.scalars(select(Circle).where(Circle.status == "active").order_by(Circle.started_at.desc())).all()
    return [circle_card(db, circle, user.id) for circle in circles if not circle_program_finished(circle) or db.scalar(select(CircleMember.id).where(CircleMember.circle_id == circle.id, CircleMember.member_id == user.id, CircleMember.status == "active")) is not None]

@app.post("/circles")
def create_circle(payload: CircleCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if user.role != "member": raise HTTPException(403, "Circles are for members")
    themes = {"new_to_city", "professional", "women_friendship", "men_friendship", "food", "travel", "fitness", "books_culture", "technology", "couples", "new_parents", "neighbourhood"}
    if payload.theme not in themes: raise HTTPException(422, "Choose one of the supported Circle themes")
    circle = Circle(id=str(uuid4()), title=payload.title, theme=payload.theme, area=payload.area, started_at=datetime.now(timezone.utc).isoformat(), created_by=user.id, max_members=payload.max_members)
    db.add(circle); db.flush()
    db.add(CircleMember(circle_id=circle.id, member_id=user.id))
    for week, title, kind, body, options in [
        (1, "Meet your circle", "written", "Introduce yourself and share what you hope to find in this group.", []),
        (2, "Share a little more", "voice", "Tell the group about a small thing that has been making you happy lately.", []),
        (3, "Plan something together", "poll", "Suggest a relaxed way to spend time together.", ["Coffee and a walk", "Shared dinner", "Museum or gallery", "Board games"]),
        (4, "Meet in person", "meetup", "Choose a welcoming local venue and make a plan to meet.", []),
    ]:
        db.add(CirclePrompt(id=str(uuid4()), circle_id=circle.id, week=week, title=title, prompt_type=kind, body=body, options=options))
    db.commit(); db.refresh(circle)
    return circle_card(db, circle, user.id)

@app.post("/circles/{circle_id}/join")
def join_circle(circle_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if user.role != "member": raise HTTPException(403, "Circles are for members")
    circle = db.get(Circle, circle_id)
    if not circle or circle.status != "active" or circle_program_finished(circle): raise HTTPException(404, "Circle is not accepting members")
    membership = db.scalar(select(CircleMember).where(CircleMember.circle_id == circle_id, CircleMember.member_id == user.id))
    if membership and membership.status == "active": return circle_card(db, circle, user.id)
    count = db.scalar(select(func.count()).select_from(CircleMember).where(CircleMember.circle_id == circle_id, CircleMember.status == "active")) or 0
    if count >= circle.max_members: raise HTTPException(409, "This Circle is full")
    if membership: membership.status = "active"
    else: db.add(CircleMember(circle_id=circle_id, member_id=user.id))
    db.commit()
    return circle_card(db, circle, user.id)

@app.post("/circles/{circle_id}/leave")
def leave_circle(circle_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    membership = db.scalar(select(CircleMember).where(CircleMember.circle_id == circle_id, CircleMember.member_id == user.id, CircleMember.status == "active"))
    if not membership: raise HTTPException(404, "Circle not found")
    membership.status = "left"; db.commit()
    return {"left": True}

@app.get("/circles/{circle_id}")
def circle_detail(circle_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    circle = require_circle_member(db, circle_id, user.id)
    week = circle_week(circle)
    prompt = db.scalar(select(CirclePrompt).where(CirclePrompt.circle_id == circle_id, CirclePrompt.week == week))
    my_response = db.scalar(select(CircleResponse).where(CircleResponse.prompt_id == prompt.id, CircleResponse.member_id == user.id)) if prompt else None
    responses = db.execute(select(CircleResponse, User.first_name).join(User, User.id == CircleResponse.member_id).where(CircleResponse.prompt_id == prompt.id).order_by(CircleResponse.created_at)) if prompt else []
    poll_counts = {option: 0 for option in (prompt.options or [])} if prompt and prompt.prompt_type == "poll" else {}
    if poll_counts:
        for saved_response in db.scalars(select(CircleResponse).where(CircleResponse.prompt_id == prompt.id)).all():
            for option in saved_response.selected_options or []:
                if option in poll_counts: poll_counts[option] += 1
    members = db.execute(select(User.first_name).join(CircleMember, CircleMember.member_id == User.id).where(CircleMember.circle_id == circle_id, CircleMember.status == "active").order_by(CircleMember.joined_at)).all()
    messages = db.execute(select(CircleMessage, User.first_name).join(User, User.id == CircleMessage.sender_id).where(CircleMessage.circle_id == circle_id).order_by(CircleMessage.created_at.desc()).limit(50)).all()
    plans = db.scalars(select(CircleMeetingPlan).where(CircleMeetingPlan.circle_id == circle_id).order_by(CircleMeetingPlan.starts_at)).all()
    return {
        **circle_card(db, circle, user.id),
        "members": [row[0] for row in members],
        "current_prompt": ({"id": prompt.id, "week": prompt.week, "title": prompt.title, "prompt_type": prompt.prompt_type, "body": prompt.body, "options": prompt.options, "poll_counts": poll_counts} if prompt else None),
        "my_response": ({"response_text": my_response.response_text, "selected_options": my_response.selected_options, "has_voice_note": bool(my_response.voice_asset_key), "voice_asset_key": my_response.voice_asset_key} if my_response else None),
        "group_responses": ([{"first_name": first_name, "response_text": response.response_text, "selected_options": response.selected_options, "has_voice_note": bool(response.voice_asset_key), "voice_asset_key": response.voice_asset_key} for response, first_name in responses] if prompt else []),
        "messages": [{"id": item.id, "sender_id": item.sender_id, "first_name": first_name, "body": item.body, "created_at": item.created_at.isoformat()} for item, first_name in reversed(messages)],
        "meeting_plans": [{"id": plan.id, "title": plan.title, "venue": plan.venue, "area": plan.area, "starts_at": plan.starts_at, "status": plan.status, "yes_count": db.scalar(select(func.count()).select_from(CircleMeetingVote).where(CircleMeetingVote.plan_id == plan.id, CircleMeetingVote.attending == True)) or 0, "no_count": db.scalar(select(func.count()).select_from(CircleMeetingVote).where(CircleMeetingVote.plan_id == plan.id, CircleMeetingVote.attending == False)) or 0, "my_vote": (db.scalar(select(CircleMeetingVote.attending).where(CircleMeetingVote.plan_id == plan.id, CircleMeetingVote.member_id == user.id)))} for plan in plans],
    }

@app.post("/circles/{circle_id}/responses")
def respond_to_circle_prompt(circle_id: str, payload: CirclePromptResponseCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    circle = require_circle_member(db, circle_id, user.id)
    prompt = db.scalar(select(CirclePrompt).where(CirclePrompt.circle_id == circle_id, CirclePrompt.week == circle_week(circle)))
    if not prompt: raise HTTPException(404, "There is no open prompt this week")
    response = db.scalar(select(CircleResponse).where(CircleResponse.prompt_id == prompt.id, CircleResponse.member_id == user.id))
    if payload.voice_asset_key:
        existing_voice = db.scalar(select(CircleResponse.id).where(CircleResponse.prompt_id == prompt.id, CircleResponse.member_id == user.id, CircleResponse.voice_asset_key == payload.voice_asset_key))
        if not existing_voice: raise HTTPException(422, "Upload your voice note before attaching it")
    if prompt.prompt_type == "poll" and (not payload.selected_options or any(option not in (prompt.options or []) for option in payload.selected_options)):
        raise HTTPException(422, "Choose one or two Circle poll options")
    if prompt.prompt_type != "poll" and payload.selected_options: raise HTTPException(422, "This prompt does not accept poll choices")
    if not payload.response_text.strip() and not payload.voice_asset_key and not (response and response.voice_asset_key) and not payload.selected_options: raise HTTPException(422, "Add a written or voice response")
    if not response:
        response = CircleResponse(prompt_id=prompt.id, member_id=user.id); db.add(response)
    response.response_text = payload.response_text.strip()
    response.selected_options = payload.selected_options
    if payload.voice_asset_key: response.voice_asset_key = payload.voice_asset_key
    db.commit()
    return {"submitted": True, "prompt_id": prompt.id, "has_voice_note": bool(response.voice_asset_key), "voice_asset_key": response.voice_asset_key}

@app.post("/circles/{circle_id}/prompts/{prompt_id}/voice-note")
async def upload_circle_voice_note(circle_id: str, prompt_id: str, request: Request, user: User = Depends(current_user), db: Session = Depends(get_db)):
    circle = require_circle_member(db, circle_id, user.id)
    prompt = db.scalar(select(CirclePrompt).where(CirclePrompt.id == prompt_id, CirclePrompt.circle_id == circle_id, CirclePrompt.week == circle_week(circle)))
    if not prompt: raise HTTPException(404, "Prompt not found")
    if request.headers.get("content-type", "").split(";")[0].strip().lower() not in {"audio/mp4", "audio/m4a"}:
        raise HTTPException(415, "Upload an AAC/M4A voice note")
    length = request.headers.get("content-length")
    if length and int(length) > 10 * 1024 * 1024: raise HTTPException(413, "Voice note must be at most 10 MB")
    data = await request.body()
    if not data or len(data) > 10 * 1024 * 1024: raise HTTPException(413 if data else 422, "Voice note must be between 1 byte and 10 MB")
    if len(data) < 12 or data[4:8] != b"ftyp": raise HTTPException(415, "The voice note is not a valid M4A audio file")
    asset_key = str(uuid4())
    media_root = Path(os.getenv("TWONEST_CIRCLE_MEDIA_DIR", str(Path(tempfile.gettempdir()) / "twonest-circle-audio")))
    media_root.mkdir(parents=True, exist_ok=True)
    (media_root / f"{asset_key}.m4a").write_bytes(data)
    response = db.scalar(select(CircleResponse).where(CircleResponse.prompt_id == prompt.id, CircleResponse.member_id == user.id))
    if not response:
        response = CircleResponse(prompt_id=prompt.id, member_id=user.id); db.add(response)
    response.voice_asset_key = asset_key
    db.commit()
    return {"submitted": True, "prompt_id": prompt.id, "has_voice_note": True, "voice_asset_key": asset_key}

@app.get("/circles/{circle_id}/voice-notes/{asset_key}")
def get_circle_voice_note(circle_id: str, asset_key: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_circle_member(db, circle_id, user.id)
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", asset_key): raise HTTPException(404, "Voice note not found")
    asset_exists = db.scalar(select(CircleResponse.id).join(CirclePrompt, CirclePrompt.id == CircleResponse.prompt_id).where(CirclePrompt.circle_id == circle_id, CircleResponse.voice_asset_key == asset_key))
    if not asset_exists: raise HTTPException(404, "Voice note not found")
    media_root = Path(os.getenv("TWONEST_CIRCLE_MEDIA_DIR", str(Path(tempfile.gettempdir()) / "twonest-circle-audio")))
    path = media_root / f"{asset_key}.m4a"
    if not path.is_file(): raise HTTPException(404, "Voice note not found")
    return FileResponse(path, media_type="audio/mp4", filename="circle-voice-note.m4a")

@app.post("/circles/{circle_id}/messages")
def send_circle_message(circle_id: str, payload: CircleMessageCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_circle_member(db, circle_id, user.id)
    message = CircleMessage(circle_id=circle_id, sender_id=user.id, body=payload.body.strip())
    db.add(message); db.commit(); db.refresh(message)
    return {"id": message.id, "sender_id": user.id, "first_name": user.first_name, "body": message.body, "created_at": message.created_at.isoformat()}

@app.post("/circles/{circle_id}/meeting-plans")
def create_circle_meeting_plan(circle_id: str, payload: CircleMeetingPlanCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    circle = require_circle_member(db, circle_id, user.id)
    if circle_week(circle) < 3: raise HTTPException(403, "Meeting planning opens in week three")
    try: starts = datetime.fromisoformat(payload.starts_at.replace("Z", "+00:00"))
    except ValueError: raise HTTPException(422, "starts_at must be an ISO 8601 date and time")
    if starts.tzinfo is None: starts = starts.replace(tzinfo=timezone.utc)
    if starts <= datetime.now(timezone.utc): raise HTTPException(422, "Meeting time must be in the future")
    plan = CircleMeetingPlan(id=str(uuid4()), circle_id=circle_id, proposed_by=user.id, title=payload.title, venue=payload.venue, area=payload.area, starts_at=starts.isoformat())
    db.add(plan); db.commit(); db.refresh(plan)
    return {"id": plan.id, "title": plan.title, "venue": plan.venue, "area": plan.area, "starts_at": plan.starts_at, "status": plan.status, "yes_count": 0, "no_count": 0, "my_vote": None}

@app.post("/circles/{circle_id}/meeting-plans/{plan_id}/vote")
def vote_circle_meeting(circle_id: str, plan_id: str, payload: CircleMeetingVoteCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_circle_member(db, circle_id, user.id)
    plan = db.scalar(select(CircleMeetingPlan).where(CircleMeetingPlan.id == plan_id, CircleMeetingPlan.circle_id == circle_id))
    if not plan: raise HTTPException(404, "Meeting plan not found")
    vote = db.scalar(select(CircleMeetingVote).where(CircleMeetingVote.plan_id == plan_id, CircleMeetingVote.member_id == user.id))
    if not vote: vote = CircleMeetingVote(plan_id=plan_id, member_id=user.id, attending=payload.attending); db.add(vote)
    else: vote.attending = payload.attending
    db.flush()
    active_count = db.scalar(select(func.count()).select_from(CircleMember).where(CircleMember.circle_id == circle_id, CircleMember.status == "active")) or 0
    yes_count = db.scalar(select(func.count()).select_from(CircleMeetingVote).where(CircleMeetingVote.plan_id == plan_id, CircleMeetingVote.attending == True)) or 0
    no_count = db.scalar(select(func.count()).select_from(CircleMeetingVote).where(CircleMeetingVote.plan_id == plan_id, CircleMeetingVote.attending == False)) or 0
    plan.status = "confirmed" if yes_count >= active_count and active_count >= 4 else ("needs_another_plan" if no_count else "proposed")
    db.commit()
    return {"status": plan.status, "yes_count": yes_count, "no_count": no_count, "votes_required": active_count}

@app.post("/conversations/{conversation_id}/messages")
def send_message(conversation_id: str,payload:MessageCreate,user:User=Depends(current_user),db:Session=Depends(get_db)):
    c=db.get(Conversation,conversation_id)
    if not c or user.id not in (c.user_a,c.user_b) or not c.active: raise HTTPException(404,"Conversation not found")
    if not payload.body.strip(): raise HTTPException(422, "Write a message before sending")
    m=Message(conversation_id=c.id,sender_id=user.id,body=payload.body.strip());db.add(m);db.commit();db.refresh(m)
    return {"id":m.id,"body":m.body,"sender_id":m.sender_id,"created_at":m.created_at.isoformat()}

@app.get("/experiences")
def experiences(user:User=Depends(current_user),db:Session=Depends(get_db)):
    result=[]
    for event in db.scalars(select(Experience)).all():
        booked=db.scalar(select(func.count()).select_from(Booking).where(Booking.experience_id==event.id,Booking.status=="confirmed")) or 0
        waiting=db.scalar(select(func.count()).select_from(ExperienceWaitlist).where(ExperienceWaitlist.experience_id==event.id,ExperienceWaitlist.status=="waiting")) or 0
        my_waitlist=db.scalar(select(ExperienceWaitlist.id).where(ExperienceWaitlist.experience_id==event.id,ExperienceWaitlist.user_id==user.id,ExperienceWaitlist.status=="waiting")) is not None
        result.append({"id":event.id,"title":event.title,"format":event.format,"venue":event.venue,"area":event.area,"starts_at":event.starts_at,"capacity":event.capacity,"spaces_remaining":max(0,event.capacity-booked),"waitlist_count":waiting,"on_waitlist":my_waitlist})
    return result

@app.post("/experiences/{experience_id}/book")
def book(experience_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    e=db.get(Experience,experience_id)
    if not e: raise HTTPException(404,"Experience not found")
    count=db.scalar(select(func.count()).select_from(Booking).where(Booking.experience_id==e.id,Booking.status=="confirmed"))
    if count>=e.capacity: raise HTTPException(409,"Experience is full; join the waitlist")
    active_booking = db.scalar(select(Booking).where(Booking.experience_id==e.id,Booking.user_id==user.id,Booking.status.in_(("confirmed", "checked_in", "checked_out"))))
    if active_booking: raise HTTPException(409,"Already booked")
    b=Booking(id=str(uuid4()),experience_id=e.id,user_id=user.id,check_code=uuid4().hex[:8].upper());db.add(b);db.commit()
    waiting=db.scalar(select(ExperienceWaitlist).where(ExperienceWaitlist.experience_id==e.id,ExperienceWaitlist.user_id==user.id,ExperienceWaitlist.status=="waiting"))
    if waiting: waiting.status="withdrawn";db.commit()
    return {"booking_id":b.id,"status":b.status,"check_code":b.check_code,"experience":e.title,"venue_revealed":True}

@app.post("/experiences/{experience_id}/waitlist")
def join_experience_waitlist(experience_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    event=db.get(Experience,experience_id)
    if not event: raise HTTPException(404,"Experience not found")
    booked=db.scalar(select(func.count()).select_from(Booking).where(Booking.experience_id==event.id,Booking.status=="confirmed")) or 0
    if booked < event.capacity: raise HTTPException(409,"There are still places available; reserve directly")
    if db.scalar(select(Booking.id).where(Booking.experience_id==event.id,Booking.user_id==user.id,Booking.status=="confirmed")): raise HTTPException(409,"You already have a reservation")
    existing=db.scalar(select(ExperienceWaitlist).where(ExperienceWaitlist.experience_id==event.id,ExperienceWaitlist.user_id==user.id))
    if existing and existing.status=="waiting": raise HTTPException(409,"You are already on the waitlist")
    if existing: existing.status="waiting";existing.created_at=datetime.now(timezone.utc)
    else: existing=ExperienceWaitlist(id=str(uuid4()),experience_id=event.id,user_id=user.id);db.add(existing)
    db.commit()
    waiting_rows=db.scalars(select(ExperienceWaitlist).where(ExperienceWaitlist.experience_id==event.id,ExperienceWaitlist.status=="waiting").order_by(ExperienceWaitlist.created_at,ExperienceWaitlist.id)).all()
    position=next(index for index,row in enumerate(waiting_rows,1) if row.id==existing.id)
    return {"status":"waiting","position":position,"experience":event.title}

@app.delete("/experiences/{experience_id}/waitlist")
def leave_experience_waitlist(experience_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    row=db.scalar(select(ExperienceWaitlist).where(ExperienceWaitlist.experience_id==experience_id,ExperienceWaitlist.user_id==user.id,ExperienceWaitlist.status=="waiting"))
    if not row: raise HTTPException(404,"Active waitlist place not found")
    row.status="withdrawn";db.commit();return {"status":"withdrawn"}

@app.get("/me/bookings")
def my_bookings(user:User=Depends(current_user),db:Session=Depends(get_db)):
    rows=db.scalars(select(Booking).where(Booking.user_id==user.id).order_by(Booking.id.desc())).all()
    return [{"booking_id":b.id,"status":b.status,"check_code":b.check_code,"experience":db.get(Experience,b.experience_id).title,"experience_id":b.experience_id,"venue_revealed":True} for b in rows]

@app.delete("/bookings/{booking_id}")
def cancel_booking(booking_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    booking=db.get(Booking,booking_id)
    if not booking or booking.user_id!=user.id: raise HTTPException(404,"Booking not found")
    if booking.status!="confirmed": raise HTTPException(409,"Only a confirmed booking can be cancelled")
    booking.status="cancelled"
    next_member=db.scalar(select(ExperienceWaitlist).where(ExperienceWaitlist.experience_id==booking.experience_id,ExperienceWaitlist.status=="waiting").order_by(ExperienceWaitlist.created_at,ExperienceWaitlist.id).limit(1))
    promoted=False
    if next_member:
        next_member.status="promoted"
        db.add(Booking(id=str(uuid4()),experience_id=booking.experience_id,user_id=next_member.user_id,status="confirmed",check_code=uuid4().hex[:8].upper()))
        promoted=True
    db.commit()
    return {"cancelled":True,"waitlist_member_promoted":promoted}

@app.post("/bookings/{booking_id}/check-in")
def check_in(booking_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    b=db.get(Booking,booking_id)
    if not b or b.user_id!=user.id: raise HTTPException(404,"Booking not found")
    if b.status!="confirmed": raise HTTPException(409,"Booking is not ready to check in")
    b.status="checked_in";db.commit();return {"status":b.status,"checked_in":True}

@app.post("/bookings/{booking_id}/check-out")
def check_out(booking_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    b=db.get(Booking,booking_id)
    if not b or b.user_id!=user.id: raise HTTPException(404,"Booking not found")
    if b.status!="checked_in": raise HTTPException(409,"Check in before checking out")
    b.status="checked_out";db.commit();return {"status":b.status,"safety_check_complete":True}

@app.post("/bookings/{booking_id}/feedback")
def event_feedback(booking_id:str,payload:Feedback,user:User=Depends(current_user),db:Session=Depends(get_db)):
    b=db.get(Booking,booking_id)
    if not b or b.user_id!=user.id or b.status!="checked_out": raise HTTPException(404,"Completed booking not found")
    b.feedback=f"{payload.rating}/5 — {payload.note}";db.commit();return {"submitted":True,"private":True,"follow_up":"You can request a second meeting from Connect."}

@app.post("/couples/invite")
def invite(payload:InvitePartner,user:User=Depends(current_user),db:Session=Depends(get_db)):
    partner=db.scalar(select(User).where(User.email==payload.partner_email.lower()))
    if not partner: raise HTTPException(404,"Partner must first create and verify their own account")
    if partner.id==user.id: raise HTTPException(422,"Invite a different account")
    couple=Couple(id=str(uuid4()),user_a=user.id,user_b=partner.id,status="invited");db.add(couple);db.commit();return {"couple_id":couple.id,"status":"invited","partner_must_accept":True}

@app.post("/couples/{couple_id}/accept")
def accept_couple(couple_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    c=db.get(Couple,couple_id)
    if not c or c.user_b!=user.id: raise HTTPException(404,"Invitation not found")
    c.status="active";db.commit();return {"couple_id":c.id,"status":c.status}

@app.get("/couples/me")
def my_couples(user:User=Depends(current_user),db:Session=Depends(get_db)):
    rows=db.scalars(select(Couple).where((Couple.user_a==user.id)|(Couple.user_b==user.id))).all()
    result=[]
    for c in rows:
        invited_to_me=c.user_b==user.id and c.status=="invited"
        other=c.user_a if c.user_b==user.id else c.user_b
        result.append({
            "id": c.id, "status": c.status, "invited_to_me": invited_to_me,
            "partner_first_name": db.get(User, other).first_name,
            "your_home_consent": c.home_a if c.user_a == user.id else c.home_b,
            "partner_home_consent": c.home_b if c.user_a == user.id else c.home_a,
            "your_home_answer_count": db.scalar(select(func.count()).select_from(HomeModeAnswer).where(HomeModeAnswer.couple_id == c.id, HomeModeAnswer.member_id == user.id)) or 0,
            "partner_home_answer_count": db.scalar(select(func.count()).select_from(HomeModeAnswer).where(HomeModeAnswer.couple_id == c.id, HomeModeAnswer.member_id == other)) or 0,
        })
    return result

@app.get("/couples/{couple_id}/nest4-candidates")
def nest4_candidates(couple_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    source=db.get(Couple,couple_id)
    if not source or user.id not in (source.user_a,source.user_b) or source.status!="active":raise HTTPException(404,"Active couple not found")
    source_profile=db.get(CoupleProfile,source.id)
    if not source_profile or not (source_profile.approved_a and source_profile.approved_b):
        raise HTTPException(403,"Both partners must approve your shared profile before exploring Nest4")
    rows=db.scalars(select(Couple).join(CoupleProfile, CoupleProfile.couple_id==Couple.id).where(Couple.id!=source.id,Couple.status=="active",CoupleProfile.approved_a==True,CoupleProfile.approved_b==True,Couple.user_a.not_in((source.user_a,source.user_b)),Couple.user_b.not_in((source.user_a,source.user_b)))).all()
    source_interests=set(source_profile.shared_interests or [])
    candidates=[]
    for couple in rows:
        profile=db.get(CoupleProfile,couple.id)
        shared=sorted(source_interests & set(profile.shared_interests or []))
        if source_profile.general_area and profile.general_area and source_profile.general_area.casefold()!=profile.general_area.casefold(): continue
        candidates.append({"couple_id":couple.id,"first_names":[db.get(User,couple.user_a).first_name,db.get(User,couple.user_b).first_name],"general_area":profile.general_area,"relationship_stage":profile.relationship_stage,"shared_interests":profile.shared_interests,"preferred_activities":profile.preferred_activities,"food_preferences":profile.food_preferences,"social_energy":profile.social_energy,"children":profile.children,"pets":profile.pets,"languages":profile.languages,"availability":profile.availability,"event_budget_min":profile.event_budget_min,"event_budget_max":profile.event_budget_max,"travel_interests":profile.travel_interests,"alignment_reasons":[f"You both enjoy {', '.join(shared[:3])}." ] if shared else ([f"You’re both based in {profile.general_area}."] if profile.general_area else ["Explore a shared interest together."])})
    return sorted(candidates,key=lambda candidate:(-len(set(candidate["shared_interests"]) & source_interests),candidate["couple_id"]))

@app.post("/couples/{couple_id}/home-mode")
def home_mode(couple_id:str,payload:Consent,user:User=Depends(current_user),db:Session=Depends(get_db)):
    c=db.get(Couple,couple_id)
    if not c or user.id not in (c.user_a,c.user_b) or c.status!="active": raise HTTPException(404,"Active couple not found")
    if user.id==c.user_a:c.home_a=payload.approved
    else:c.home_b=payload.approved
    db.commit();return {"your_consent":payload.approved,"active":c.home_a and c.home_b}

def require_active_couple(db: Session, couple_id: str, member_id: str) -> Couple:
    couple = db.get(Couple, couple_id)
    if not couple or couple.status != "active" or member_id not in (couple.user_a, couple.user_b):
        raise HTTPException(404, "Active couple not found")
    return couple

def couple_profile_payload(couple: Couple, profile: CoupleProfile | None, member_id: str):
    values = {
        "relationship_stage": "dating", "general_area": "", "shared_interests": [],
        "preferred_activities": [], "food_preferences": [], "social_energy": "",
        "children": "", "pets": [], "languages": [], "availability": [],
        "event_budget_min": 0, "event_budget_max": 100, "travel_interests": [],
    }
    if profile:
        for key in values: values[key] = getattr(profile, key)
    you_approved = bool(profile and (profile.approved_a if member_id == couple.user_a else profile.approved_b))
    partner_approved = bool(profile and (profile.approved_b if member_id == couple.user_a else profile.approved_a))
    return {"profile": values, "has_profile": profile is not None, "approved_by_you": you_approved, "approved_by_partner": partner_approved, "published": you_approved and partner_approved}

@app.get("/couples/{couple_id}/together")
def get_together(couple_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    couple = require_active_couple(db, couple_id, user.id)
    profile = db.get(CoupleProfile, couple_id)
    return couple_profile_payload(couple, profile, user.id)

@app.put("/couples/{couple_id}/together")
def save_together(couple_id: str, payload: CoupleProfileInput, user: User = Depends(current_user), db: Session = Depends(get_db)):
    couple = require_active_couple(db, couple_id, user.id)
    if payload.event_budget_min > payload.event_budget_max: raise HTTPException(422, "Minimum event budget must not exceed the maximum")
    profile = db.get(CoupleProfile, couple_id)
    if profile is None:
        profile = CoupleProfile(couple_id=couple_id)
    values = {}
    for key, value in payload.model_dump().items():
        values[key] = sorted({item.strip() for item in value if item.strip()}) if isinstance(value, list) else value.strip() if isinstance(value, str) else value
    changed = any(
        (set(getattr(profile, key) or []) != set(value)) if isinstance(value, list) else getattr(profile, key) != value
        for key, value in values.items()
    )
    for key, value in values.items(): setattr(profile, key, value)
    if changed:
        profile.approved_a = False; profile.approved_b = False
    db.add(profile); db.commit(); db.refresh(profile)
    return couple_profile_payload(couple, profile, user.id)

@app.post("/couples/{couple_id}/together/consent")
def consent_together(couple_id: str, payload: Consent, user: User = Depends(current_user), db: Session = Depends(get_db)):
    couple = require_active_couple(db, couple_id, user.id)
    profile = db.get(CoupleProfile, couple_id)
    if profile is None: raise HTTPException(409, "Save your shared couple profile before approving publication")
    if user.id == couple.user_a: profile.approved_a = payload.approved
    else: profile.approved_b = payload.approved
    db.commit(); db.refresh(profile)
    return couple_profile_payload(couple, profile, user.id)

@app.get("/couples/{couple_id}/moments")
def list_couple_moments(couple_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_active_couple(db, couple_id, user.id)
    rows = db.scalars(select(CoupleMoment).where(CoupleMoment.couple_id == couple_id).order_by(CoupleMoment.planned_for.is_(None), CoupleMoment.planned_for, CoupleMoment.created_at)).all()
    return [{"id": row.id, "title": row.title, "details": row.details, "moment_type": row.moment_type, "planned_for": row.planned_for, "completed": row.completed} for row in rows]

@app.post("/couples/{couple_id}/moments")
def create_couple_moment(couple_id: str, payload: CoupleMomentCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_active_couple(db, couple_id, user.id)
    if payload.moment_type not in {"activity", "date", "milestone"}: raise HTTPException(422, "Choose activity, date, or milestone")
    if payload.planned_for:
        try: datetime.fromisoformat(payload.planned_for.replace("Z", "+00:00"))
        except ValueError: raise HTTPException(422, "Use an ISO date or date-time")
    row = CoupleMoment(id=str(uuid4()), couple_id=couple_id, created_by=user.id, title=payload.title.strip(), details=payload.details.strip(), moment_type=payload.moment_type, planned_for=payload.planned_for)
    db.add(row); db.commit(); db.refresh(row)
    return {"id": row.id, "title": row.title, "details": row.details, "moment_type": row.moment_type, "planned_for": row.planned_for, "completed": row.completed}

@app.patch("/couples/{couple_id}/moments/{moment_id}")
def update_couple_moment(couple_id: str, moment_id: str, payload: CoupleMomentUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_active_couple(db, couple_id, user.id)
    row = db.scalar(select(CoupleMoment).where(CoupleMoment.id == moment_id, CoupleMoment.couple_id == couple_id))
    if not row: raise HTTPException(404, "Shared moment not found")
    row.completed = payload.completed; db.commit()
    return {"id": row.id, "completed": row.completed}

def home_mode_questions():
    return [question for group in QUESTION_GROUPS for question in group["questions"] if question["category"] == "home_life"]

@app.get("/couples/{couple_id}/home-questionnaire")
def get_home_questionnaire(couple_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_active_couple(db, couple_id, user.id)
    rows = db.scalars(select(HomeModeAnswer).where(HomeModeAnswer.couple_id == couple_id, HomeModeAnswer.member_id == user.id)).all()
    return {
        "groups": [{"id": "home_life", "title": "The way you want to live", "questions": home_mode_questions()}],
        "answers": [{"question_id": row.question_id, "value": row.value, "is_private": row.is_private} for row in rows],
    }

@app.put("/couples/{couple_id}/home-questionnaire/answers")
def save_home_questionnaire(couple_id: str, payload: HomeModeAnswerBatch, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_active_couple(db, couple_id, user.id)
    seen = set()
    for item in payload.answers:
        if item.question_id in seen: raise HTTPException(422, "Each home question can be saved once per request")
        seen.add(item.question_id)
        question = QUESTION_BY_ID.get(item.question_id)
        if not question or question["category"] != "home_life": raise HTTPException(422, "Choose a supported home question")
        if not _questionnaire_answer_is_valid(question, item.value): raise HTTPException(422, f"Answer format is invalid for {item.question_id}")
        row = db.scalar(select(HomeModeAnswer).where(HomeModeAnswer.couple_id == couple_id, HomeModeAnswer.member_id == user.id, HomeModeAnswer.question_id == item.question_id))
        if row is None:
            row = HomeModeAnswer(couple_id=couple_id, member_id=user.id, question_id=item.question_id, value=item.value)
        row.value = item.value
        row.is_private = item.is_private
        db.add(row)
    db.commit()
    count = db.scalar(select(func.count()).select_from(HomeModeAnswer).where(HomeModeAnswer.couple_id == couple_id, HomeModeAnswer.member_id == user.id)) or 0
    return {"saved": len(payload.answers), "answer_count": count, "total_questions": len(home_mode_questions())}

def _home_question_title(question_id: str) -> str:
    titles = {
        "pets": "pets", "sleep_schedule": "sleep schedules", "cleanliness": "cleanliness",
        "cooking_at_home": "cooking at home", "working_from_home": "working from home",
        "guests_at_home": "hosting guests", "personal_space": "personal space",
        "neighbourhood_preferences": "neighbourhood priorities", "rent_budget": "rent budget",
        "moving_timeline": "moving timeline",
    }
    return titles.get(question_id, question_id.replace("_", " "))

def _home_compromise(question_id: str) -> str:
    suggestions = {
        "pets": "Talk through future pet plans, including care and costs.",
        "sleep_schedule": "Agree on quiet hours and how to handle different sleep routines.",
        "cleanliness": "Choose a shared baseline for chores and decide what you will outsource.",
        "cooking_at_home": "Plan a weekly rhythm for shared meals, cooking and takeaway.",
        "working_from_home": "Map out work-from-home days and where each person can focus.",
        "guests_at_home": "Set expectations for visits, notice and overnight guests.",
        "personal_space": "Make room for both shared time and independent space.",
        "neighbourhood_preferences": "Pick a few neighbourhoods and compare the things each of you values nearby.",
        "rent_budget": "Set a comfortable rent ceiling together, including bills and savings.",
        "moving_timeline": "Talk about what would need to feel true before moving in together.",
    }
    return suggestions.get(question_id, "Talk through what would make this feel workable for both of you.")

@app.get("/couples/{couple_id}/living-report")
def living_report(couple_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    couple = require_active_couple(db, couple_id, user.id)
    if not (couple.home_a and couple.home_b): raise HTTPException(403,"Both partners must activate Home Mode")
    left_id, right_id = couple.user_a, couple.user_b
    answers = db.scalars(select(HomeModeAnswer).where(HomeModeAnswer.couple_id == couple_id)).all()
    by_member = {left_id: {}, right_id: {}}
    for answer in answers:
        if answer.member_id in by_member:
            by_member[answer.member_id][answer.question_id] = answer
    questions = home_mode_questions()
    total = len(questions)
    left_count, right_count = len(by_member[left_id]), len(by_member[right_id])
    strong_alignment, acceptable_differences, discuss_early, compromises, conversation_prompts = [], [], [], [], []
    compared = 0
    for question in questions:
        key = question["id"]
        left, right = by_member[left_id].get(key), by_member[right_id].get(key)
        if not left or not right or left.is_private or right.is_private:
            continue
        first, second = left.value, right.value
        if first == "Prefer to discuss privately" or second == "Prefer to discuss privately":
            continue
        compared += 1
        label = _home_question_title(key)
        tier = "discuss"
        if first == second:
            tier = "strong"
        elif question["response_type"] == "scale" and isinstance(first, int) and isinstance(second, int):
            gap = abs(first - second)
            tier = "strong" if gap <= 1 else "acceptable" if gap == 2 else "discuss"
        elif question["response_type"] == "ranking" and isinstance(first, list) and isinstance(second, list):
            overlap = set(first[:3]) & set(second[:3])
            tier = "strong" if len(overlap) >= 2 else "acceptable" if overlap else "discuss"
        elif key == "rent_budget" and first in question["options"] and second in question["options"]:
            distance = abs(question["options"].index(first) - question["options"].index(second))
            tier = "acceptable" if distance == 1 else "discuss"
        if tier == "strong":
            strong_alignment.append(f"You have similar views on {label.lower()}.")
        elif tier == "acceptable":
            acceptable_differences.append(f"You have some room to find a shared approach to {label.lower()}.")
            compromises.append(_home_compromise(key))
        else:
            discuss_early.append(f"Make time to talk about {label.lower()}.")
            compromises.append(_home_compromise(key))
            conversation_prompts.append(question["prompt"])
    if compared == 0:
        discuss_early.append("Answer and choose to share a few home questions each to build your report.")
    if not compromises and compared:
        compromises.append("Keep checking in as your plans and circumstances change.")
    return {
        "stage": "home_mode", "status": "ready" if left_count == total and right_count == total else "in_progress",
        "disclaimer": "A conversation guide based on answers you chose to share, not a decision about your relationship.",
        "your_answer_count": len(by_member[user.id]),
        "partner_answer_count": len(by_member[right_id if user.id == left_id else left_id]),
        "total_questions": total, "shared_answer_count": compared,
        "strong_alignment": strong_alignment, "acceptable_differences": acceptable_differences,
        "discuss_early": discuss_early, "compromises": compromises,
        "conversation_prompts": conversation_prompts[:5],
    }

@app.post("/couples/{couple_id}/nest4/{other_couple_id}")
def propose_nest4(couple_id:str,other_couple_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    a=db.get(Couple,couple_id);b=db.get(Couple,other_couple_id)
    if not a or not b or a.id==b.id or user.id not in (a.user_a,a.user_b) or a.status!="active" or b.status!="active": raise HTTPException(404,"Two active couples are required")
    existing=db.scalar(select(CoupleMatch).where(((CoupleMatch.couple_a==a.id)&(CoupleMatch.couple_b==b.id))|((CoupleMatch.couple_a==b.id)&(CoupleMatch.couple_b==a.id))))
    if existing:return {"match_id":existing.id,"status":existing.status}
    match=CoupleMatch(id=str(uuid4()),couple_a=a.id,couple_b=b.id);db.add(match);db.commit();return {"match_id":match.id,"status":match.status,"consents_required":4}

@app.post("/nest4/{match_id}/decision")
def decide_nest4(match_id:str,payload:Consent,user:User=Depends(current_user),db:Session=Depends(get_db)):
    m=db.get(CoupleMatch,match_id)
    if not m:raise HTTPException(404,"Nest4 introduction not found")
    if m.status != "pending": raise HTTPException(409, "This Nest4 introduction is no longer awaiting decisions")
    a=db.get(Couple,m.couple_a);b=db.get(Couple,m.couple_b)
    if user.id not in (a.user_a,a.user_b,b.user_a,b.user_b):raise HTTPException(403,"Only one of the four members can decide")
    row=db.scalar(select(CoupleMatchDecision).where(CoupleMatchDecision.match_id==m.id,CoupleMatchDecision.member_id==user.id)) or CoupleMatchDecision(match_id=m.id,member_id=user.id,approved=payload.approved)
    row.approved=payload.approved;db.add(row)
    db.flush()
    if not payload.approved:m.status="closed"
    else:
        decisions=db.scalars(select(CoupleMatchDecision).where(CoupleMatchDecision.match_id==m.id)).all()
        all_ids={a.user_a,a.user_b,b.user_a,b.user_b}
        if len([d for d in decisions if d.approved and d.member_id in all_ids])==4:m.status="matched"
    db.commit();return {"status":m.status,"your_choice_saved":True,"group_chat_open":m.status=="connected"}

def require_nest4_member(db: Session, match_id: str, member_id: str) -> tuple[CoupleMatch, Couple, Couple, set[str]]:
    match = db.get(CoupleMatch, match_id)
    if not match: raise HTTPException(404, "Nest4 introduction not found")
    couple_a, couple_b = db.get(Couple, match.couple_a), db.get(Couple, match.couple_b)
    if not couple_a or not couple_b or member_id not in (couple_a.user_a, couple_a.user_b, couple_b.user_a, couple_b.user_b):
        raise HTTPException(404, "Nest4 introduction not found")
    return match, couple_a, couple_b, {couple_a.user_a, couple_a.user_b, couple_b.user_a, couple_b.user_b}

def nest4_plan_payload(db: Session, plan: Nest4MeetingPlan, member_id: str):
    votes = db.scalars(select(Nest4MeetingVote).where(Nest4MeetingVote.plan_id == plan.id)).all()
    return {"id": plan.id, "title": plan.title, "venue": plan.venue, "area": plan.area,
            "starts_at": plan.starts_at, "status": plan.status,
            "attending_count": sum(1 for vote in votes if vote.attending),
            "declined_count": sum(1 for vote in votes if not vote.attending),
            "my_vote": next((vote.attending for vote in votes if vote.member_id == member_id), None)}

@app.post("/nest4/{match_id}/meeting-plans")
def create_nest4_meeting_plan(match_id: str, payload: Nest4MeetingPlanCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    match, _, _, _ = require_nest4_member(db, match_id, user.id)
    if match.status != "matched": raise HTTPException(409, "All four members must approve before planning a Nest4 meetup")
    try:
        starts_at = datetime.fromisoformat(payload.starts_at.replace("Z", "+00:00"))
    except ValueError: raise HTTPException(422, "Meetup time must be an ISO 8601 date and time")
    if starts_at.tzinfo is None: starts_at = starts_at.replace(tzinfo=timezone.utc)
    if starts_at <= datetime.now(timezone.utc): raise HTTPException(422, "Choose a future meetup time")
    plan = Nest4MeetingPlan(id=str(uuid4()), match_id=match.id, created_by=user.id,
                            title=payload.title.strip(), venue=payload.venue.strip(), area=payload.area.strip(),
                            starts_at=starts_at.isoformat())
    db.add(plan); db.commit(); db.refresh(plan)
    return nest4_plan_payload(db, plan, user.id)

@app.post("/nest4/{match_id}/meeting-plans/{plan_id}/vote")
def vote_nest4_meeting_plan(match_id: str, plan_id: str, payload: Nest4MeetingVoteInput, user: User = Depends(current_user), db: Session = Depends(get_db)):
    match, _, _, member_ids = require_nest4_member(db, match_id, user.id)
    plan = db.scalar(select(Nest4MeetingPlan).where(Nest4MeetingPlan.id == plan_id, Nest4MeetingPlan.match_id == match_id))
    if not plan: raise HTTPException(404, "Nest4 meetup plan not found")
    if match.status != "matched" or plan.status not in {"proposed", "scheduled"}:
        raise HTTPException(409, "This meetup plan is no longer open for votes")
    vote = db.scalar(select(Nest4MeetingVote).where(Nest4MeetingVote.plan_id == plan.id, Nest4MeetingVote.member_id == user.id))
    if vote is None:
        vote = Nest4MeetingVote(plan_id=plan.id, member_id=user.id, attending=payload.attending)
    vote.attending = payload.attending; db.add(vote); db.flush()
    votes = db.scalars(select(Nest4MeetingVote).where(Nest4MeetingVote.plan_id == plan.id)).all()
    if any(not row.attending for row in votes): plan.status = "declined"
    elif len([row for row in votes if row.attending and row.member_id in member_ids]) == 4: plan.status = "scheduled"
    db.commit()
    return nest4_plan_payload(db, plan, user.id)

@app.post("/nest4/{match_id}/meeting-plans/{plan_id}/complete")
def complete_nest4_meeting(match_id: str, plan_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    match, _, _, _ = require_nest4_member(db, match_id, user.id)
    plan = db.scalar(select(Nest4MeetingPlan).where(Nest4MeetingPlan.id == plan_id, Nest4MeetingPlan.match_id == match_id))
    if not plan or plan.status != "scheduled": raise HTTPException(409, "The meetup must be agreed by all four members first")
    starts_at = datetime.fromisoformat(plan.starts_at.replace("Z", "+00:00"))
    if starts_at.tzinfo is None: starts_at = starts_at.replace(tzinfo=timezone.utc)
    if starts_at > datetime.now(timezone.utc): raise HTTPException(409, "Post-meet decisions open after the planned meetup time")
    if match.status != "matched": raise HTTPException(409, "This Nest4 connection is no longer active")
    plan.status = "held"; match.status = "meeting_complete"; db.commit()
    return {"status": match.status, "meeting_status": plan.status, "follow_up_open": True}

@app.get("/nest4/{match_id}/follow-up")
def get_nest4_followup(match_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    match, _, _, member_ids = require_nest4_member(db, match_id, user.id)
    own = db.scalar(select(Nest4FollowupDecision).where(Nest4FollowupDecision.match_id == match_id, Nest4FollowupDecision.member_id == user.id))
    count = db.scalar(select(func.count()).select_from(Nest4FollowupDecision).where(Nest4FollowupDecision.match_id == match_id)) or 0
    return {"status": match.status, "your_decision": own.decision if own else None,
            "decisions_received": min(count, len(member_ids)), "decisions_required": len(member_ids),
            "group_chat_open": match.status == "connected"}

@app.post("/nest4/{match_id}/follow-up")
def submit_nest4_followup(match_id: str, payload: Nest4FollowupInput, user: User = Depends(current_user), db: Session = Depends(get_db)):
    match, couple_a, couple_b, member_ids = require_nest4_member(db, match_id, user.id)
    if match.status != "meeting_complete": raise HTTPException(409, "Complete the agreed Nest4 meetup before choosing what happens next")
    choices = {"meet_again", "invite_activity", "couple_circle", "no_connection", "report_concern"}
    if payload.decision not in choices: raise HTTPException(422, "Choose a supported private follow-up")
    details = payload.details.strip()
    if payload.decision == "report_concern" and len(details) < 10: raise HTTPException(422, "Add at least 10 characters so the safety team can review your concern")
    row = db.scalar(select(Nest4FollowupDecision).where(Nest4FollowupDecision.match_id == match_id, Nest4FollowupDecision.member_id == user.id))
    if row is None: row = Nest4FollowupDecision(match_id=match_id, member_id=user.id, decision=payload.decision)
    row.decision = payload.decision; row.details = details; db.add(row)
    if payload.decision == "report_concern":
        own_couple = couple_a if user.id in (couple_a.user_a, couple_a.user_b) else couple_b
        other_couple = couple_b if own_couple.id == couple_a.id else couple_a
        for subject_id in (other_couple.user_a, other_couple.user_b):
            db.add(SafetyReport(id=str(uuid4()), reporter_id=user.id, subject_id=subject_id,
                                category="nest4_meetup_concern", details=details))
        match.status = "closed"
    elif payload.decision == "no_connection":
        match.status = "closed"
    else:
        db.flush()
        decisions = db.scalars(select(Nest4FollowupDecision).where(Nest4FollowupDecision.match_id == match_id)).all()
        if len([decision for decision in decisions if decision.member_id in member_ids and decision.decision in {"meet_again", "invite_activity", "couple_circle"}]) == 4:
            match.status = "connected"
    db.commit()
    count = db.scalar(select(func.count()).select_from(Nest4FollowupDecision).where(Nest4FollowupDecision.match_id == match_id)) or 0
    return {"status": match.status, "your_decision": row.decision,
            "decisions_received": min(count, len(member_ids)), "decisions_required": len(member_ids),
            "group_chat_open": match.status == "connected"}

@app.get("/nest4/{match_id}/messages")
def nest4_messages(match_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    match, couple_a, couple_b, _ = require_nest4_member(db, match_id, user.id)
    if match.status != "connected": raise HTTPException(403, "All four people must choose to continue before group chat opens")
    rows = db.execute(select(Nest4Message, User.first_name).join(User, User.id == Nest4Message.sender_id).where(Nest4Message.match_id == match_id).order_by(Nest4Message.created_at).limit(100)).all()
    return [{"id": message.id, "sender_id": message.sender_id, "first_name": first_name,
             "body": message.body, "created_at": message.created_at.isoformat()} for message, first_name in rows]

@app.post("/nest4/{match_id}/messages")
def send_nest4_message(match_id: str, payload: Nest4GroupMessageCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    match, _, _, _ = require_nest4_member(db, match_id, user.id)
    if match.status != "connected": raise HTTPException(403, "All four people must choose to continue before group chat opens")
    body = payload.body.strip()
    if not body: raise HTTPException(422, "Message cannot be empty")
    message = Nest4Message(match_id=match_id, sender_id=user.id, body=body); db.add(message); db.commit(); db.refresh(message)
    return {"id": message.id, "sender_id": message.sender_id, "first_name": user.first_name,
            "body": message.body, "created_at": message.created_at.isoformat()}

@app.get("/nest4")
def my_nest4(user:User=Depends(current_user),db:Session=Depends(get_db)):
    couple_ids=db.scalars(select(Couple.id).where((Couple.user_a==user.id)|(Couple.user_b==user.id))).all()
    rows=db.scalars(select(CoupleMatch).where((CoupleMatch.couple_a.in_(couple_ids))|(CoupleMatch.couple_b.in_(couple_ids)))).all()
    result=[]
    for match in rows:
        other_id=match.couple_b if match.couple_a in couple_ids else match.couple_a
        other=db.get(Couple,other_id)
        decisions = db.scalars(select(CoupleMatchDecision).where(CoupleMatchDecision.match_id == match.id)).all()
        meeting = db.scalar(select(Nest4MeetingPlan).where(Nest4MeetingPlan.match_id == match.id).order_by(Nest4MeetingPlan.created_at.desc()))
        own_followup = db.scalar(select(Nest4FollowupDecision).where(Nest4FollowupDecision.match_id == match.id, Nest4FollowupDecision.member_id == user.id))
        result.append({
            "match_id": match.id, "status": match.status,
            "other_first_names": [db.get(User, other.user_a).first_name, db.get(User, other.user_b).first_name],
            "your_choice": next((decision.approved for decision in decisions if decision.member_id == user.id), None),
            "approval_count": sum(1 for decision in decisions if decision.approved),
            "meeting_plan": nest4_plan_payload(db, meeting, user.id) if meeting else None,
            "your_followup": own_followup.decision if own_followup else None,
            "followup_count": db.scalar(select(func.count()).select_from(Nest4FollowupDecision).where(Nest4FollowupDecision.match_id == match.id)) or 0,
        })
    return result

@app.post("/safety/reports")
def safety_report(payload:SafetyReportCreate,user:User=Depends(current_user),db:Session=Depends(get_db)):
    if not db.get(User,payload.subject_id) or payload.subject_id==user.id:raise HTTPException(422,"Choose another member")
    r=SafetyReport(id=str(uuid4()),reporter_id=user.id,subject_id=payload.subject_id,category=payload.category,details=payload.details);db.add(r);db.commit()
    return {"report_id":r.id,"status":r.status,"private":True,"next_step":"Our safety team will review this report."}

@app.get("/admin/safety-reports")
def safety_queue(user:User=Depends(require_roles("administrator","moderator")),db:Session=Depends(get_db)):
    return [{"id":r.id,"reporter_id":r.reporter_id,"subject_id":r.subject_id,"category":r.category,"status":r.status,"created_at":r.created_at.isoformat()} for r in db.scalars(select(SafetyReport).order_by(SafetyReport.created_at.desc())).all()]

@app.get("/admin/safety-reports/{report_id}")
def safety_case(report_id:str,user:User=Depends(require_roles("administrator","moderator")),db:Session=Depends(get_db)):
    r=db.get(SafetyReport,report_id)
    if not r:raise HTTPException(404,"Safety case not found")
    return {"id":r.id,"reporter":public_user(db,r.reporter_id)["first_name"],"subject":public_user(db,r.subject_id)["first_name"],"category":r.category,"details":r.details,"status":r.status,"created_at":r.created_at.isoformat()}

@app.get("/properties")
def properties(user:User=Depends(current_user),db:Session=Depends(get_db)):
    return [{"id":p.id,"title":p.title,"area":p.area,"rent_pcm":p.rent_pcm,"bedrooms":p.bedrooms,"verified":p.verified} for p in db.scalars(select(Property).where(Property.verified==True)).all()]

@app.post("/couples/{couple_id}/properties/{property_id}/shortlist")
def shortlist(couple_id:str,property_id:str,payload:Consent,user:User=Depends(current_user),db:Session=Depends(get_db)):
    c=db.get(Couple,couple_id);p=db.get(Property,property_id)
    if not c or user.id not in (c.user_a,c.user_b) or not(c.home_a and c.home_b): raise HTTPException(403,"Couple Home Mode access required")
    if not p or not p.verified: raise HTTPException(404,"Verified property not found")
    row=db.scalar(select(Shortlist).where(Shortlist.couple_id==c.id,Shortlist.property_id==p.id))
    if not row: row=Shortlist(couple_id=c.id,property_id=p.id,added_by=user.id);db.add(row)
    row.vote="interested" if payload.approved else "not_interested";db.commit();return {"property_id":p.id,"vote":row.vote,"shared_with_partner":True}

@app.post("/couples/{couple_id}/properties/{property_id}/viewings")
def schedule_viewing(couple_id:str,property_id:str,payload:ViewingCreate,user:User=Depends(current_user),db:Session=Depends(get_db)):
    c=db.get(Couple,couple_id)
    if not c or user.id not in (c.user_a,c.user_b) or not(c.home_a and c.home_b): raise HTTPException(403,"Couple Home Mode access required")
    if not db.scalar(select(Shortlist).where(Shortlist.couple_id==c.id,Shortlist.property_id==property_id)): raise HTTPException(409,"Add the property to your shared shortlist first")
    v=Viewing(id=str(uuid4()),couple_id=c.id,property_id=property_id,starts_at=payload.starts_at);db.add(v);db.commit();return {"viewing_id":v.id,"status":v.status,"starts_at":v.starts_at}

def require_moving_workspace(db: Session, couple_id: str, member_id: str) -> Couple:
    couple = require_active_couple(db, couple_id, member_id)
    if not (couple.home_a and couple.home_b):
        raise HTTPException(403, "Both partners must activate Home Mode")
    return couple

@app.get("/couples/{couple_id}/moving-tasks")
def list_moving_tasks(couple_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    couple = require_moving_workspace(db, couple_id, user.id)
    tasks = db.scalars(select(MovingTask).where(MovingTask.couple_id == couple_id).order_by(MovingTask.category, MovingTask.created_at)).all()
    if not tasks:
        defaults = [
            ("Agree on a comfortable total monthly budget", "budget"),
            ("Compare neighbourhoods and commute times", "home_search"),
            ("List documents needed for an application", "documents"),
            ("Estimate deposit and moving costs", "budget"),
            ("Plan utilities and address changes", "move_day"),
            ("Make a first-week essentials list", "move_day"),
        ]
        tasks = [MovingTask(id=str(uuid4()), couple_id=couple_id, title=title, category=category, created_by=couple.user_a) for title, category in defaults]
        db.add_all(tasks)
        db.commit()
        for task in tasks: db.refresh(task)
    return [{"id": t.id, "title": t.title, "category": t.category, "due_date": t.due_date, "completed": t.completed} for t in tasks]

@app.post("/couples/{couple_id}/moving-tasks")
def create_moving_task(couple_id: str, payload: MovingTaskCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_moving_workspace(db, couple_id, user.id)
    if payload.due_date:
        try: datetime.strptime(payload.due_date, "%Y-%m-%d")
        except ValueError: raise HTTPException(422, "Due date must use YYYY-MM-DD")
    task = MovingTask(id=str(uuid4()), couple_id=couple_id, title=payload.title.strip(), category=payload.category.strip().lower().replace(" ", "_"), due_date=payload.due_date, created_by=user.id)
    db.add(task); db.commit(); db.refresh(task)
    return {"id": task.id, "title": task.title, "category": task.category, "due_date": task.due_date, "completed": task.completed}

@app.patch("/couples/{couple_id}/moving-tasks/{task_id}")
def update_moving_task(couple_id: str, task_id: str, payload: MovingTaskUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    require_moving_workspace(db, couple_id, user.id)
    task = db.scalar(select(MovingTask).where(MovingTask.id == task_id, MovingTask.couple_id == couple_id))
    if not task: raise HTTPException(404, "Moving task not found")
    task.completed = payload.completed
    db.commit()
    return {"id": task.id, "completed": task.completed}

@app.get("/partner/bookings")
def partner_bookings(user:User=Depends(require_roles("restaurant_partner","administrator")),db:Session=Depends(get_db)):
    owned_experiences = select(Experience.id).where(Experience.partner_id==user.id)
    bookings = db.scalars(select(Booking).where(Booking.experience_id.in_(owned_experiences))).all()
    return [{"booking_id":b.id,"experience":db.get(Experience,b.experience_id).title,"status":b.status,"check_code":b.check_code} for b in bookings]

@app.get("/admin/operations")
def admin_operations(user:User=Depends(require_roles("administrator","moderator","customer_support")),db:Session=Depends(get_db)):
    return {"members":db.scalar(select(func.count()).select_from(User)),"introductions":db.scalar(select(func.count()).select_from(Introduction)),"bookings":db.scalar(select(func.count()).select_from(Booking)),"active_couples":db.scalar(select(func.count()).select_from(Couple).where(Couple.status=="active"))}
