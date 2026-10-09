from datetime import datetime, timezone
from sqlalchemy import Boolean, DateTime, ForeignKey, Float, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from .db import Base

def now(): return datetime.now(timezone.utc)

class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    first_name: Mapped[str] = mapped_column(String(80))
    role: Mapped[str] = mapped_column(String(32), default="member")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

class Profile(Base):
    __tablename__ = "profiles"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    intention: Mapped[str] = mapped_column(String(40), default="serious_dating")
    bio: Mapped[str] = mapped_column(Text, default="")
    area: Mapped[str] = mapped_column(String(100), default="East London")
    interests: Mapped[str] = mapped_column(Text, default="cooking,quiet weekends")
    complete: Mapped[bool] = mapped_column(Boolean, default=False)
    visibility: Mapped[str] = mapped_column(String(24), default="matches")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)

class OnboardingProfile(Base):
    __tablename__ = "onboarding_profiles"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    date_of_birth: Mapped[str | None] = mapped_column(String(10), nullable=True)
    pronouns: Mapped[str] = mapped_column(String(40), default="")
    gender_identity: Mapped[str] = mapped_column(String(60), default="")
    sexual_orientation: Mapped[str] = mapped_column(String(60), default="")
    dating_preferences: Mapped[list[str]] = mapped_column(JSON, default=list)
    friendship_intention: Mapped[str] = mapped_column(String(60), default="")
    search_radius_km: Mapped[int] = mapped_column(Integer, default=40)
    preferred_age_min: Mapped[int] = mapped_column(Integer, default=18)
    preferred_age_max: Mapped[int] = mapped_column(Integer, default=80)
    onboarding_step: Mapped[int] = mapped_column(Integer, default=0)
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    languages: Mapped[list[str]] = mapped_column(JSON, default=list)
    availability: Mapped[list[str]] = mapped_column(JSON, default=list)
    dietary_requirements: Mapped[list[str]] = mapped_column(JSON, default=list)
    accessibility_needs: Mapped[list[str]] = mapped_column(JSON, default=list)
    event_budget_min: Mapped[int] = mapped_column(Integer, default=0)
    event_budget_max: Mapped[int] = mapped_column(Integer, default=100)
    discovery_paused: Mapped[bool] = mapped_column(Boolean, default=False)
    travel_mode_area: Mapped[str] = mapped_column(String(100), default="")
    travel_mode_until: Mapped[str | None] = mapped_column(String(10), nullable=True)

class CompatibilityAnswer(Base):
    __tablename__ = "compatibility_answers"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    question_id: Mapped[str] = mapped_column(String(80))
    category: Mapped[str] = mapped_column(String(40))
    value: Mapped[object] = mapped_column(JSON)
    importance: Mapped[int] = mapped_column(Integer, default=1)
    deal_breaker: Mapped[bool] = mapped_column(Boolean, default=False)
    is_private: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)
    __table_args__ = (UniqueConstraint("user_id", "question_id"),)

class Verification(Base):
    __tablename__ = "verifications"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(40))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    provider_ref: Mapped[str | None] = mapped_column(String(120), nullable=True)

class Introduction(Base):
    __tablename__ = "introductions"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    candidate_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    score: Mapped[int] = mapped_column(Integer, default=82)
    label: Mapped[str] = mapped_column(String(40), default="Strong Alignment")
    reasons: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[str] = mapped_column(String(20), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    __table_args__ = (UniqueConstraint("user_id", "candidate_id"),)

class Conversation(Base):
    __tablename__ = "conversations"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_a: Mapped[str] = mapped_column(ForeignKey("users.id"))
    user_b: Mapped[str] = mapped_column(ForeignKey("users.id"))
    active: Mapped[bool] = mapped_column(Boolean, default=True)

class Message(Base):
    __tablename__ = "messages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    conversation_id: Mapped[str] = mapped_column(ForeignKey("conversations.id"), index=True)
    sender_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class Experience(Base):
    __tablename__ = "experiences"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    title: Mapped[str] = mapped_column(String(120))
    format: Mapped[str] = mapped_column(String(40))
    venue: Mapped[str] = mapped_column(String(120))
    area: Mapped[str] = mapped_column(String(100))
    starts_at: Mapped[str] = mapped_column(String(40))
    capacity: Mapped[int] = mapped_column(Integer, default=12)
    partner_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)

class Booking(Base):
    __tablename__ = "bookings"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    experience_id: Mapped[str] = mapped_column(ForeignKey("experiences.id"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    status: Mapped[str] = mapped_column(String(24), default="confirmed")
    check_code: Mapped[str] = mapped_column(String(12))
    feedback: Mapped[str | None] = mapped_column(Text, nullable=True)

class ExperienceWaitlist(Base):
    __tablename__ = "experience_waitlist"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    experience_id: Mapped[str] = mapped_column(ForeignKey("experiences.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(24), default="waiting")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    __table_args__ = (UniqueConstraint("experience_id", "user_id"),)

class Couple(Base):
    __tablename__ = "couples"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_a: Mapped[str] = mapped_column(ForeignKey("users.id"))
    user_b: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    status: Mapped[str] = mapped_column(String(24), default="invited")
    home_a: Mapped[bool] = mapped_column(Boolean, default=False)
    home_b: Mapped[bool] = mapped_column(Boolean, default=False)

class CoupleProfile(Base):
    __tablename__ = "couple_profiles"
    couple_id: Mapped[str] = mapped_column(ForeignKey("couples.id", ondelete="CASCADE"), primary_key=True)
    relationship_stage: Mapped[str] = mapped_column(String(40), default="dating")
    general_area: Mapped[str] = mapped_column(String(100), default="")
    shared_interests: Mapped[list[str]] = mapped_column(JSON, default=list)
    preferred_activities: Mapped[list[str]] = mapped_column(JSON, default=list)
    food_preferences: Mapped[list[str]] = mapped_column(JSON, default=list)
    social_energy: Mapped[str] = mapped_column(String(40), default="")
    children: Mapped[str] = mapped_column(String(80), default="")
    pets: Mapped[list[str]] = mapped_column(JSON, default=list)
    languages: Mapped[list[str]] = mapped_column(JSON, default=list)
    availability: Mapped[list[str]] = mapped_column(JSON, default=list)
    event_budget_min: Mapped[int] = mapped_column(Integer, default=0)
    event_budget_max: Mapped[int] = mapped_column(Integer, default=100)
    travel_interests: Mapped[list[str]] = mapped_column(JSON, default=list)
    approved_a: Mapped[bool] = mapped_column(Boolean, default=False)
    approved_b: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)

class CoupleMoment(Base):
    __tablename__ = "couple_moments"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    couple_id: Mapped[str] = mapped_column(ForeignKey("couples.id", ondelete="CASCADE"), index=True)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(120))
    details: Mapped[str] = mapped_column(Text, default="")
    moment_type: Mapped[str] = mapped_column(String(24), default="activity")
    planned_for: Mapped[str | None] = mapped_column(String(40), nullable=True)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)

class HomeModeAnswer(Base):
    __tablename__ = "home_mode_answers"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    couple_id: Mapped[str] = mapped_column(ForeignKey("couples.id", ondelete="CASCADE"), index=True)
    member_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    question_id: Mapped[str] = mapped_column(String(80))
    value: Mapped[object] = mapped_column(JSON)
    is_private: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)
    __table_args__ = (UniqueConstraint("couple_id", "member_id", "question_id"),)

class Nest4Decision(Base):
    __tablename__ = "nest4_decisions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    couple_id: Mapped[str] = mapped_column(ForeignKey("couples.id"), index=True)
    member_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    approved: Mapped[bool] = mapped_column(Boolean)
    __table_args__ = (UniqueConstraint("couple_id", "member_id"),)

class CoupleMatch(Base):
    __tablename__ = "couple_matches"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    couple_a: Mapped[str] = mapped_column(ForeignKey("couples.id"))
    couple_b: Mapped[str] = mapped_column(ForeignKey("couples.id"))
    status: Mapped[str] = mapped_column(String(24), default="pending")

class Nest4MeetingPlan(Base):
    __tablename__ = "nest4_meeting_plans"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    match_id: Mapped[str] = mapped_column(ForeignKey("couple_matches.id", ondelete="CASCADE"), index=True)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    title: Mapped[str] = mapped_column(String(120))
    venue: Mapped[str] = mapped_column(String(160))
    area: Mapped[str] = mapped_column(String(100))
    starts_at: Mapped[str] = mapped_column(String(40))
    status: Mapped[str] = mapped_column(String(24), default="proposed")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class Nest4MeetingVote(Base):
    __tablename__ = "nest4_meeting_votes"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    plan_id: Mapped[str] = mapped_column(ForeignKey("nest4_meeting_plans.id", ondelete="CASCADE"), index=True)
    member_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    attending: Mapped[bool] = mapped_column(Boolean)
    __table_args__ = (UniqueConstraint("plan_id", "member_id"),)

class Nest4FollowupDecision(Base):
    __tablename__ = "nest4_followup_decisions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    match_id: Mapped[str] = mapped_column(ForeignKey("couple_matches.id", ondelete="CASCADE"), index=True)
    member_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    decision: Mapped[str] = mapped_column(String(32))
    details: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)
    __table_args__ = (UniqueConstraint("match_id", "member_id"),)

class Nest4Message(Base):
    __tablename__ = "nest4_messages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    match_id: Mapped[str] = mapped_column(ForeignKey("couple_matches.id", ondelete="CASCADE"), index=True)
    sender_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class CoupleMatchDecision(Base):
    __tablename__ = "couple_match_decisions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    match_id: Mapped[str] = mapped_column(ForeignKey("couple_matches.id", ondelete="CASCADE"), index=True)
    member_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    approved: Mapped[bool] = mapped_column(Boolean)
    __table_args__ = (UniqueConstraint("match_id", "member_id"),)

class SafetyReport(Base):
    __tablename__ = "safety_reports"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    reporter_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    subject_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    category: Mapped[str] = mapped_column(String(40))
    details: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(24), default="open")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class MemberBlock(Base):
    __tablename__ = "member_blocks"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    blocker_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    blocked_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    __table_args__ = (UniqueConstraint("blocker_id", "blocked_id"),)

class Property(Base):
    __tablename__ = "properties"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    title: Mapped[str] = mapped_column(String(140))
    area: Mapped[str] = mapped_column(String(100))
    rent_pcm: Mapped[int] = mapped_column(Integer)
    bedrooms: Mapped[int] = mapped_column(Integer)
    partner_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    verified: Mapped[bool] = mapped_column(Boolean, default=True)

class Shortlist(Base):
    __tablename__ = "shortlists"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    couple_id: Mapped[str] = mapped_column(ForeignKey("couples.id"), index=True)
    property_id: Mapped[str] = mapped_column(ForeignKey("properties.id"))
    added_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    note: Mapped[str] = mapped_column(Text, default="")
    vote: Mapped[str] = mapped_column(String(20), default="considering")
    __table_args__ = (UniqueConstraint("couple_id", "property_id"),)

class Viewing(Base):
    __tablename__ = "viewings"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    couple_id: Mapped[str] = mapped_column(ForeignKey("couples.id"))
    property_id: Mapped[str] = mapped_column(ForeignKey("properties.id"))
    starts_at: Mapped[str] = mapped_column(String(40))
    status: Mapped[str] = mapped_column(String(24), default="requested")

class MovingTask(Base):
    __tablename__ = "moving_tasks"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    couple_id: Mapped[str] = mapped_column(ForeignKey("couples.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(160))
    category: Mapped[str] = mapped_column(String(40), default="planning")
    due_date: Mapped[str | None] = mapped_column(String(10), nullable=True)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)

class Circle(Base):
    __tablename__ = "circles"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    title: Mapped[str] = mapped_column(String(120))
    theme: Mapped[str] = mapped_column(String(48), index=True)
    area: Mapped[str] = mapped_column(String(100))
    started_at: Mapped[str] = mapped_column(String(40))
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    status: Mapped[str] = mapped_column(String(24), default="active", index=True)
    max_members: Mapped[int] = mapped_column(Integer, default=8)

class CircleMember(Base):
    __tablename__ = "circle_members"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id", ondelete="CASCADE"), index=True)
    member_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    status: Mapped[str] = mapped_column(String(24), default="active")
    __table_args__ = (UniqueConstraint("circle_id", "member_id"),)

class CirclePrompt(Base):
    __tablename__ = "circle_prompts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id", ondelete="CASCADE"), index=True)
    week: Mapped[int] = mapped_column(Integer)
    title: Mapped[str] = mapped_column(String(120))
    prompt_type: Mapped[str] = mapped_column(String(24))
    body: Mapped[str] = mapped_column(Text)
    options: Mapped[list[str]] = mapped_column(JSON, default=list)
    __table_args__ = (UniqueConstraint("circle_id", "week"),)

class CircleResponse(Base):
    __tablename__ = "circle_responses"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    prompt_id: Mapped[str] = mapped_column(ForeignKey("circle_prompts.id", ondelete="CASCADE"), index=True)
    member_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    response_text: Mapped[str] = mapped_column(Text, default="")
    selected_options: Mapped[list[str]] = mapped_column(JSON, default=list)
    voice_asset_key: Mapped[str | None] = mapped_column(String(80), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    __table_args__ = (UniqueConstraint("prompt_id", "member_id"),)

class CircleMessage(Base):
    __tablename__ = "circle_messages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id", ondelete="CASCADE"), index=True)
    sender_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class CircleMeetingPlan(Base):
    __tablename__ = "circle_meeting_plans"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id", ondelete="CASCADE"), index=True)
    proposed_by: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(120))
    venue: Mapped[str] = mapped_column(String(160))
    area: Mapped[str] = mapped_column(String(100))
    starts_at: Mapped[str] = mapped_column(String(40))
    status: Mapped[str] = mapped_column(String(24), default="proposed")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class CircleMeetingVote(Base):
    __tablename__ = "circle_meeting_votes"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    plan_id: Mapped[str] = mapped_column(ForeignKey("circle_meeting_plans.id", ondelete="CASCADE"), index=True)
    member_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    attending: Mapped[bool] = mapped_column(Boolean)
    __table_args__ = (UniqueConstraint("plan_id", "member_id"),)

class ActivityAvailability(Base):
    __tablename__ = "activity_availability"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    area: Mapped[str] = mapped_column(String(100), default="")
    categories: Mapped[list[str]] = mapped_column(JSON, default=list)
    mode: Mapped[str] = mapped_column(String(16), default="both")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    show_on_map: Mapped[bool] = mapped_column(Boolean, default=False)

class ActivityRequest(Base):
    __tablename__ = "activity_requests"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    host_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    category: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(Text, default="")
    mode: Mapped[str] = mapped_column(String(16), default="in_person")
    area: Mapped[str] = mapped_column(String(100), default="")
    meeting_details: Mapped[str] = mapped_column(String(500), default="")
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    meeting_latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    meeting_longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    meeting_name: Mapped[str] = mapped_column(String(200), default="")
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    companion_limit: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(24), default="open")
    revision: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class ActivityJoin(Base):
    __tablename__ = "activity_joins"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    request_id: Mapped[str] = mapped_column(ForeignKey("activity_requests.id", ondelete="CASCADE"), index=True)
    member_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    note: Mapped[str] = mapped_column(String(300), default="")
    status: Mapped[str] = mapped_column(String(24), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    __table_args__ = (UniqueConstraint("request_id", "member_id"),)

class ActivityMessage(Base):
    __tablename__ = "activity_messages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    request_id: Mapped[str] = mapped_column(ForeignKey("activity_requests.id", ondelete="CASCADE"), index=True)
    sender_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
