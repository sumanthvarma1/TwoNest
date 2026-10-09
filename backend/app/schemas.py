from pydantic import BaseModel, Field
from typing import Any
from typing import Any

class DevLogin(BaseModel):
    email: str

class DevSignup(BaseModel):
    email: str = Field(min_length=3, max_length=254)

class ProfileUpdate(BaseModel):
    intention: str = "serious_dating"
    bio: str = Field(default="", max_length=600)
    area: str = "East London"
    interests: list[str] = Field(default_factory=list)
    complete: bool = True
    visibility: str = "matches"

class OnboardingUpdate(BaseModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=80)
    date_of_birth: str | None = None
    pronouns: str | None = Field(default=None, max_length=40)
    gender_identity: str | None = Field(default=None, max_length=60)
    sexual_orientation: str | None = Field(default=None, max_length=60)
    dating_preferences: list[str] | None = None
    intention: str | None = Field(default=None, max_length=40)
    friendship_intention: str | None = Field(default=None, max_length=60)
    area: str | None = Field(default=None, max_length=100)
    search_radius_km: int | None = Field(default=None, ge=1, le=250)
    preferred_age_min: int | None = Field(default=None, ge=18, le=120)
    preferred_age_max: int | None = Field(default=None, ge=18, le=120)
    onboarding_step: int | None = Field(default=None, ge=0, le=7)
    languages: list[str] | None = None
    availability: list[str] | None = None
    dietary_requirements: list[str] | None = None
    accessibility_needs: list[str] | None = None
    event_budget_min: int | None = Field(default=None, ge=0, le=10000)
    event_budget_max: int | None = Field(default=None, ge=0, le=10000)
    discovery_paused: bool | None = None
    travel_mode_area: str | None = Field(default=None, max_length=100)
    travel_mode_until: str | None = Field(default=None, max_length=10)
    bio: str | None = Field(default=None, max_length=600)
    interests: list[str] | None = None
    visibility: str | None = Field(default=None, max_length=24)

class CompatibilityAnswerInput(BaseModel):
    question_id: str = Field(min_length=1, max_length=80)
    value: Any
    importance: int = Field(default=1, ge=1, le=3)
    deal_breaker: bool = False
    is_private: bool = False

class CompatibilityAnswerBatch(BaseModel):
    answers: list[CompatibilityAnswerInput] = Field(min_length=1, max_length=50)

class Decision(BaseModel):
    decision: str

class MessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=4000)

class VerificationUpdate(BaseModel):
    status: str = "approved"

class InvitePartner(BaseModel):
    partner_email: str

class Consent(BaseModel):
    approved: bool

class CoupleProfileInput(BaseModel):
    relationship_stage: str = Field(default="dating", min_length=2, max_length=40)
    general_area: str = Field(default="", max_length=100)
    shared_interests: list[str] = Field(default_factory=list, max_length=30)
    preferred_activities: list[str] = Field(default_factory=list, max_length=30)
    food_preferences: list[str] = Field(default_factory=list, max_length=20)
    social_energy: str = Field(default="", max_length=40)
    children: str = Field(default="", max_length=80)
    pets: list[str] = Field(default_factory=list, max_length=20)
    languages: list[str] = Field(default_factory=list, max_length=20)
    availability: list[str] = Field(default_factory=list, max_length=20)
    event_budget_min: int = Field(default=0, ge=0, le=10000)
    event_budget_max: int = Field(default=100, ge=0, le=10000)
    travel_interests: list[str] = Field(default_factory=list, max_length=30)

class CoupleMomentCreate(BaseModel):
    title: str = Field(min_length=2, max_length=120)
    details: str = Field(default="", max_length=1200)
    moment_type: str = Field(default="activity", max_length=24)
    planned_for: str | None = Field(default=None, max_length=40)

class CoupleMomentUpdate(BaseModel):
    completed: bool

class HomeModeAnswerInput(BaseModel):
    question_id: str = Field(min_length=1, max_length=80)
    value: Any
    is_private: bool = False

class HomeModeAnswerBatch(BaseModel):
    answers: list[HomeModeAnswerInput] = Field(min_length=1, max_length=30)

class Nest4MeetingPlanCreate(BaseModel):
    title: str = Field(min_length=3, max_length=120)
    venue: str = Field(min_length=2, max_length=160)
    area: str = Field(min_length=2, max_length=100)
    starts_at: str = Field(min_length=10, max_length=40)

class Nest4MeetingVoteInput(BaseModel):
    attending: bool

class Nest4FollowupInput(BaseModel):
    decision: str = Field(min_length=3, max_length=32)
    details: str = Field(default="", max_length=4000)

class Nest4GroupMessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=4000)

class Feedback(BaseModel):
    rating: int = Field(ge=1, le=5)
    note: str = Field(default="", max_length=1200)

class ViewingCreate(BaseModel):
    starts_at: str

class MovingTaskCreate(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    category: str = Field(default="planning", min_length=2, max_length=40)
    due_date: str | None = Field(default=None, max_length=10)

class MovingTaskUpdate(BaseModel):
    completed: bool

class SafetyReportCreate(BaseModel):
    subject_id: str
    category: str = Field(min_length=1, max_length=40)
    details: str = Field(min_length=10, max_length=4000)

class CircleCreate(BaseModel):
    title: str = Field(min_length=4, max_length=120)
    theme: str = Field(min_length=2, max_length=48)
    area: str = Field(min_length=2, max_length=100)
    max_members: int = Field(default=8, ge=4, le=12)

class CirclePromptResponseCreate(BaseModel):
    response_text: str = Field(default="", max_length=2000)
    voice_asset_key: str | None = Field(default=None, max_length=80)
    selected_options: list[str] = Field(default_factory=list, max_length=2)

class CircleMessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=2000)

class CircleMeetingPlanCreate(BaseModel):
    title: str = Field(min_length=3, max_length=120)
    venue: str = Field(min_length=2, max_length=160)
    area: str = Field(min_length=2, max_length=100)
    starts_at: str = Field(min_length=10, max_length=40)

class CircleMeetingVoteCreate(BaseModel):
    attending: bool

class ActivityCreate(BaseModel):
    category: str = Field(min_length=2, max_length=32)
    title: str = Field(min_length=3, max_length=120)
    description: str = Field(default="", max_length=1000)
    mode: str = "in_person"
    area: str = Field(default="", max_length=100)
    meeting_details: str = Field(default="", max_length=500)
    latitude: float | None = Field(default=None, ge=-85, le=85)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    meeting_name: str = Field(default="", max_length=200)
    starts_at: str
    discovery_minutes: int = Field(default=60, ge=15, le=1440)
    companion_limit: int = Field(default=1, ge=1, le=5)

class ActivityJoinInput(BaseModel):
    note: str = Field(default="", max_length=300)

class ActivityJoinDecision(BaseModel):
    accepted: bool

class ActivityStateInput(BaseModel):
    action: str

class ActivityAvailabilityInput(BaseModel):
    enabled: bool
    area: str = Field(default="", max_length=100)
    categories: list[str] = Field(default_factory=list, max_length=12)
    mode: str = "both"
    duration_minutes: int = Field(default=60, ge=15, le=240)
    show_on_map: bool = False
    latitude: float | None = Field(default=None, ge=-85, le=85)
    longitude: float | None = Field(default=None, ge=-180, le=180)

class ActivityMessageInput(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class ActivityInviteInput(BaseModel):
    member_id: str = Field(min_length=1, max_length=36)

class TravelInput(BaseModel):
    origin_latitude: float = Field(ge=-85, le=85)
    origin_longitude: float = Field(ge=-180, le=180)
    transit_mode: str = "all"
