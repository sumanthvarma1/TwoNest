from copy import deepcopy
from app.matching import Answer, MemberSnapshot, eligibility, score_match


def pair():
    common={
        'goals':{'timeline':Answer('long-term',2)},
        'values':{'family':Answer('important',1.5)},
        'lifestyle':{'weekend':Answer('quiet')},
        'communication':{'style':Answer('direct')},
        'home_life':{'cooking':Answer('often')},
    }
    a=MemberSnapshot('a',31,'serious_dating',{'b'},51.52,-0.08,availability={'weekends'},answers=common,interests={'cooking','museums'},verified=True,profile_completeness=.9)
    b=MemberSnapshot('b',33,'serious_dating',{'a'},51.53,-0.09,availability={'weekends'},answers=deepcopy(common),interests={'cooking','walking'},verified=True,profile_completeness=.9)
    return a,b


def test_scoring_is_weighted_and_explainable():
    result=score_match(*pair())
    assert result.eligible and result.score >= 75
    assert result.label == 'Strong Alignment'
    assert any('cooking' in reason for reason in result.reasons)
    assert result.discussion_topics


def test_hard_filters_and_private_deal_breaker_handling():
    a,b=pair()
    a.answers['goals']['timeline']=Answer('within_year',2,deal_breaker=True)
    b.answers['goals']['timeline']=Answer('later',2)
    assert eligibility(a,b)=='deal_breaker:timeline'
    a,b=pair();a.blocked_ids.add('b');assert eligibility(a,b)=='blocked'
    a,b=pair();a.answers['goals']['timeline']=Answer('within_year',2,deal_breaker=True,private=True)
    b.answers['goals']['timeline']=Answer('later',2)
    assert eligibility(a,b) is None


def test_member_preferences_and_area_fallback_work_without_precise_location():
    a,b=pair()
    a.seeking={'woman'};a.gender_identity='man';a.latitude=a.longitude=None;a.area='Hackney'
    b.seeking={'man'};b.gender_identity='woman';b.latitude=b.longitude=None;b.area='Hackney'
    result=score_match(a,b)
    assert result.eligible
    same_area_score=result.score
    b.area='Walthamstow'
    assert score_match(a,b).score < same_area_score
    b.gender_identity='man'
    assert eligibility(a,b)=='not_mutually_seeking'
