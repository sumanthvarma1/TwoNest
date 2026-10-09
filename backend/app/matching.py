"""Explainable, deterministic first-release compatibility scoring; no ML training."""
from dataclasses import dataclass, field
from math import asin, cos, radians, sin, sqrt
from typing import Any

WEIGHTS = {
    "goals": .25,
    "values": .20,
    "lifestyle": .15,
    "communication": .15,
    "interests": .10,
    "location_availability": .10,
    "home_life": .05,
}

@dataclass(frozen=True)
class Answer:
    value: Any
    importance: float = 1.0
    deal_breaker: bool = False
    private: bool = False

@dataclass
class MemberSnapshot:
    member_id: str
    age: int
    intention: str
    seeking: set[str]
    latitude: float | None
    longitude: float | None
    preferred_age_min: int = 18
    preferred_age_max: int = 80
    gender_identity: str = ""
    area: str = ""
    search_radius_km: float = 40
    availability: set[str] = field(default_factory=set)
    answers: dict[str, dict[str, Answer]] = field(default_factory=dict)
    interests: set[str] = field(default_factory=set)
    blocked_ids: set[str] = field(default_factory=set)
    safety_eligible: bool = True
    active: bool = True
    history_ids: set[str] = field(default_factory=set)
    verified: bool = False
    profile_completeness: float = .5

@dataclass(frozen=True)
class MatchResult:
    eligible: bool
    score: int
    label: str
    reasons: tuple[str, ...]
    discussion_topics: tuple[str, ...]
    rejection_reason: str | None = None


def distance_km(a: MemberSnapshot, b: MemberSnapshot) -> float | None:
    """Great-circle distance for coarse eligibility; never reveal exact coordinates."""
    if None in (a.latitude, a.longitude, b.latitude, b.longitude): return None
    lat1, lat2 = radians(a.latitude), radians(b.latitude)
    dlat, dlon = lat2-lat1, radians(b.longitude-a.longitude)
    hav = sin(dlat/2)**2 + cos(lat1)*cos(lat2)*sin(dlon/2)**2
    return 6371 * 2 * asin(sqrt(hav))


def eligibility(a: MemberSnapshot, b: MemberSnapshot) -> str | None:
    if a.member_id == b.member_id: return "same_member"
    if not a.active or not b.active: return "inactive"
    if not a.safety_eligible or not b.safety_eligible: return "safety_restriction"
    if b.member_id in a.blocked_ids or a.member_id in b.blocked_ids: return "blocked"
    if b.member_id in a.history_ids or a.member_id in b.history_ids: return "already_recommended"
    if not 18 <= a.age <= 120 or not 18 <= b.age <= 120: return "under_18"
    if not a.preferred_age_min <= b.age <= a.preferred_age_max or not b.preferred_age_min <= a.age <= b.preferred_age_max: return "outside_preferred_age"
    if a.intention != b.intention: return "different_intention"
    if not _seeks(a,b) or not _seeks(b,a): return "not_mutually_seeking"
    distance = distance_km(a,b)
    if distance is not None and distance > min(a.search_radius_km,b.search_radius_km): return "outside_search_radius"
    if a.availability and b.availability and not a.availability.intersection(b.availability): return "no_shared_availability"
    for member, candidate in ((a, b), (b, a)):
        for category, answers in member.answers.items():
            other = candidate.answers.get(category, {})
            for key, answer in answers.items():
                if answer.private or not answer.deal_breaker: continue
                counterpart = other.get(key)
                if counterpart is None or counterpart.private or answer.value != counterpart.value:
                    return f"deal_breaker:{key}"
    return None


def _seeks(member: MemberSnapshot, candidate: MemberSnapshot) -> bool:
    if not member.seeking or "*" in member.seeking or candidate.member_id in member.seeking:
        return True
    wanted = {item.strip().casefold().replace("_", " ") for item in member.seeking}
    gender = candidate.gender_identity.strip().casefold().replace("_", " ")
    aliases = {"nonbinary": "non binary", "non-binary": "non binary"}
    gender = aliases.get(gender, gender)
    wanted = {aliases.get(item, item) for item in wanted}
    return gender in wanted or "any" in wanted


def _similarity(left: Any, right: Any) -> float:
    if left is None or right is None: return .5
    if isinstance(left, (int,float)) and isinstance(right,(int,float)):
        return max(0.0, 1.0 - min(abs(float(left)-float(right))/4.0,1.0))
    if isinstance(left,(list,set,tuple)) and isinstance(right,(list,set,tuple)):
        a,b=set(left),set(right)
        return len(a&b)/len(a|b) if a|b else 1.0
    return 1.0 if str(left).strip().casefold()==str(right).strip().casefold() else 0.0


def _ranking_similarity(left: list[str], right: list[str]) -> float:
    if not left or not right: return .5
    left_rank={value:index for index,value in enumerate(left)}
    right_rank={value:index for index,value in enumerate(right)}
    common=set(left_rank)&set(right_rank)
    if not common:return 0.0
    scale=max(len(left),len(right),1)
    return sum(max(0.0,1.0-abs(left_rank[value]-right_rank[value])/scale) for value in common)/len(common)


def _category_score(a: MemberSnapshot,b: MemberSnapshot,category: str) -> float:
    left=a.answers.get(category,{})
    right=b.answers.get(category,{})
    if category == "interests":
        return _similarity(a.interests,b.interests)
    if category == "location_availability":
        radius=max(1.0,min(a.search_radius_km,b.search_radius_km))
        distance=distance_km(a,b)
        if distance is None:
            distance_score = 1.0 if a.area.strip().casefold() and a.area.strip().casefold() == b.area.strip().casefold() else .5
        else:
            distance_score=max(0.0,1.0-distance/radius)
        availability_score=1.0 if a.availability and b.availability and a.availability&b.availability else .5
        return .7*distance_score + .3*availability_score
    keys=set(left)&set(right)
    if not keys:return .5
    earned=total=0.0
    for key in keys:
        x,y=left[key],right[key]
        if x.private or y.private:continue
        if key == "what_im_building": continue
        weight=max(.1,min(3.0,(x.importance+y.importance)/2))
        if key == "neighbourhood_preferences" and isinstance(x.value,list) and isinstance(y.value,list):
            similarity=_ranking_similarity(x.value,y.value)
        else:
            similarity=_similarity(x.value,y.value)
        earned += similarity*weight;total += weight
    return earned/total if total else .5


def score_match(a: MemberSnapshot,b: MemberSnapshot) -> MatchResult:
    rejected=eligibility(a,b)
    if rejected:return MatchResult(False,0,"Not eligible",(),(),rejected)
    parts={category:_category_score(a,b,category) for category in WEIGHTS}
    score=round(100*sum(WEIGHTS[name]*parts[name] for name in WEIGHTS))
    # Small, capped quality adjustment; quality cannot override hard eligibility or answers.
    completeness=(max(0,min(1,a.profile_completeness))+max(0,min(1,b.profile_completeness)))/2
    score=min(100,max(0,round(score + (2 if a.verified and b.verified else 0) + (completeness-.5)*4)))
    label="Strong Alignment" if score>=75 else "Worth Exploring" if score>=55 else "Discuss Early"
    reasons=[];topics=[]
    for category in ("goals","interests","values","lifestyle","communication","location_availability","home_life"):
        if category=="interests" and a.interests&b.interests:
            reasons.append("share interests such as " + ", ".join(sorted(a.interests&b.interests)[:3]))
        elif parts[category]>=.67:
            if category=="goals":reasons.append("both have the same relationship intention")
            elif category=="location_availability":reasons.append("share an area and availability" if distance_km(a,b) is None else "live within a workable distance and share availability")
            elif category=="home_life":reasons.append("show early alignment on home-life preferences")
            else:reasons.append(f"show alignment on {category.replace('_',' ')}")
        elif parts[category]<.45:topics.append(category.replace('_',' '))
    if not reasons:reasons.append("have a few answers and interests in common")
    if not topics:topics.append("learn more about how your routines fit together")
    return MatchResult(True,score,label,tuple(reasons[:4]),tuple(topics[:4]))
