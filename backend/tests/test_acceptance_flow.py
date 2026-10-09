import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
os.environ["DATABASE_URL"] = "sqlite:////tmp/twonest_acceptance_test.db"
os.environ["ENVIRONMENT"] = "test"
Path("/tmp/twonest_acceptance_test.db").unlink(missing_ok=True)
from fastapi.testclient import TestClient
from app.main import app
from app.db import SessionLocal
from app.models import Nest4MeetingPlan, Experience


def test_introduction_mutual_chat_and_experience_flow():
    with TestClient(app) as client:
        alex = client.post('/auth/dev-login', json={'email':'alex@twonest.test'}).json()['access_token']
        sam = client.post('/auth/dev-login', json={'email':'sam@twonest.test'}).json()['access_token']
        a = {'Authorization':f'Bearer {alex}'}; s = {'Authorization':f'Bearer {sam}'}
        intro = client.get('/introductions',headers=a).json()[0]
        assert intro['candidate']['first_name'] == 'Sam'
        assert 'both want a long-term relationship' in intro['reasons']
        assert client.post(f"/introductions/{intro['id']}/decision",headers=a,json={'decision':'interested'}).json()['mutual'] is False
        reverse=client.get('/introductions',headers=s).json()[0]
        mutual=client.post(f"/introductions/{reverse['id']}/decision",headers=s,json={'decision':'interested'}).json()
        assert mutual['mutual'] is True
        sent=client.post(f"/conversations/{mutual['conversation_id']}/messages",headers=a,json={'body':'Would you like to meet for dinner?'}).json()
        assert sent['body']=='Would you like to meet for dinner?'
        experience=client.get('/experiences',headers=a).json()[0]
        booking=client.post(f"/experiences/{experience['id']}/book",headers=a).json()
        assert booking['status']=='confirmed'
        assert client.post(f"/bookings/{booking['booking_id']}/check-in",headers=a).json()['checked_in']
        assert client.post(f"/bookings/{booking['booking_id']}/check-out",headers=a).json()['safety_check_complete']
        assert client.post(f"/bookings/{booking['booking_id']}/feedback",headers=a,json={'rating':5,'note':'Lovely evening'}).json()['private']


def test_experience_waitlist_fifo_promotion_and_booking_isolation():
    with TestClient(app) as client:
        tokens={email:client.post('/auth/dev-login',json={'email':email}).json()['access_token'] for email in ('alex@twonest.test','sam@twonest.test','jamie@twonest.test')}
        def h(email): return {'Authorization':f"Bearer {tokens[email]}"}
        db=SessionLocal(); event=Experience(id='experience-waitlist-test',title='Waitlist test dinner',format='curated_date',venue='Test venue',area='East London',starts_at='2026-11-01T18:00:00Z',capacity=1); db.add(event); db.commit(); db.close()
        experience_id='experience-waitlist-test'
        first=client.post(f'/experiences/{experience_id}/book',headers=h('alex@twonest.test')).json()
        event_state=next(row for row in client.get('/experiences',headers=h('sam@twonest.test')).json() if row['id']==experience_id)
        assert event_state['spaces_remaining']==0
        one=client.post(f'/experiences/{experience_id}/waitlist',headers=h('sam@twonest.test'))
        two=client.post(f'/experiences/{experience_id}/waitlist',headers=h('jamie@twonest.test'))
        assert one.json()['position']==1 and two.json()['position']==2
        assert client.post(f'/experiences/{experience_id}/waitlist',headers=h('sam@twonest.test')).status_code==409
        assert client.delete(f"/bookings/{first['booking_id']}",headers=h('sam@twonest.test')).status_code==404
        cancelled=client.delete(f"/bookings/{first['booking_id']}",headers=h('alex@twonest.test'))
        assert cancelled.json()=={'cancelled':True,'waitlist_member_promoted':True}
        sam_bookings=client.get('/me/bookings',headers=h('sam@twonest.test')).json()
        sam_booking=next(row for row in sam_bookings if row['experience_id']==experience_id)
        assert sam_booking['status']=='confirmed'
        event_state=next(row for row in client.get('/experiences',headers=h('sam@twonest.test')).json() if row['id']==experience_id)
        assert event_state['on_waitlist'] is False
        second=client.delete(f"/bookings/{sam_booking['booking_id']}",headers=h('sam@twonest.test'))
        assert second.json()['waitlist_member_promoted'] is True
        jamie_bookings=client.get('/me/bookings',headers=h('jamie@twonest.test')).json()
        assert next(row for row in jamie_bookings if row['experience_id']==experience_id)['status']=='confirmed'


def test_both_partners_must_consent_before_home_mode_and_property_access():
    with TestClient(app) as client:
        alex=client.post('/auth/dev-login',json={'email':'alex@twonest.test'}).json()['access_token'];sam=client.post('/auth/dev-login',json={'email':'sam@twonest.test'}).json()['access_token']
        a={'Authorization':f'Bearer {alex}'};s={'Authorization':f'Bearer {sam}'}
        couple=client.post('/couples/invite',headers=a,json={'partner_email':'sam@twonest.test'}).json();cid=couple['couple_id']
        assert client.post(f'/couples/{cid}/accept',headers=s).json()['status']=='active'
        assert client.get(f'/couples/{cid}/living-report',headers=a).status_code==403
        assert client.get(f'/couples/{cid}/moving-tasks',headers=a).status_code==403
        assert client.post(f'/couples/{cid}/home-mode',headers=a,json={'approved':True}).json()['active'] is False
        assert client.post(f'/couples/{cid}/home-mode',headers=s,json={'approved':True}).json()['active'] is True
        assert client.get(f'/couples/{cid}/living-report',headers=a).status_code==200
        tasks = client.get(f'/couples/{cid}/moving-tasks',headers=a)
        assert tasks.status_code == 200 and len(tasks.json()) == 6
        first_task = tasks.json()[0]
        assert client.patch(f'/couples/{cid}/moving-tasks/{first_task["id"]}',headers=s,json={'completed':True}).json()['completed'] is True
        added = client.post(f'/couples/{cid}/moving-tasks',headers=a,json={'title':'Book a van','category':'move_day'}).json()
        assert added['title'] == 'Book a van'
        assert any(row['id'] == first_task['id'] and row['completed'] for row in client.get(f'/couples/{cid}/moving-tasks',headers=s).json())
        prop=client.get('/properties',headers=a).json()[0]
        assert client.post(f'/couples/{cid}/properties/{prop["id"]}/shortlist',headers=a,json={'approved':True}).json()['vote']=='interested'
        view=client.post(f'/couples/{cid}/properties/{prop["id"]}/viewings',headers=s,json={'starts_at':'2026-10-20T18:00:00+01:00'})
        assert view.status_code==200


def test_couple_profile_publication_requires_both_partners_and_moments_are_shared():
    with TestClient(app) as client:
        alex=client.post('/auth/dev-login',json={'email':'alex@twonest.test'}).json()['access_token']
        sam=client.post('/auth/dev-login',json={'email':'sam@twonest.test'}).json()['access_token']
        jamie=client.post('/auth/dev-login',json={'email':'jamie@twonest.test'}).json()['access_token']
        a={'Authorization':f'Bearer {alex}'};s={'Authorization':f'Bearer {sam}'};j={'Authorization':f'Bearer {jamie}'}
        cid=client.post('/couples/invite',headers=a,json={'partner_email':'sam@twonest.test'}).json()['couple_id']
        client.post(f'/couples/{cid}/accept',headers=s)
        initial=client.get(f'/couples/{cid}/together',headers=a).json()
        assert initial['published'] is False and initial['approved_by_you'] is False
        profile={'relationship_stage':'established','general_area':'Hackney','shared_interests':['cooking','museums'],'preferred_activities':['coffee walks'],'food_preferences':['vegetarian'],'social_energy':'balanced','children':'Open to discussing','pets':['cats'],'languages':['English'],'availability':['weekends'],'event_budget_min':20,'event_budget_max':80,'travel_interests':['coastal breaks']}
        saved=client.put(f'/couples/{cid}/together',headers=a,json=profile)
        assert saved.status_code==200 and saved.json()['published'] is False
        assert client.post(f'/couples/{cid}/together/consent',headers=a,json={'approved':True}).json()['published'] is False
        published=client.post(f'/couples/{cid}/together/consent',headers=s,json={'approved':True})
        assert published.json()['published'] is True and published.json()['approved_by_partner'] is True
        reordered={**profile,'shared_interests':['museums','cooking']}
        unchanged=client.put(f'/couples/{cid}/together',headers=a,json=reordered).json()
        assert unchanged['published'] is True, 'Order-only edits must not invalidate either partner’s approval'
        assert client.get(f'/couples/{cid}/together',headers=j).status_code==404
        changed={**profile,'general_area':'Islington'}
        revised=client.put(f'/couples/{cid}/together',headers=a,json=changed).json()
        assert revised['published'] is False and not revised['approved_by_you'] and not revised['approved_by_partner']
        assert client.post(f'/couples/{cid}/together/consent',headers=a,json={'approved':True}).json()['published'] is False
        assert client.post(f'/couples/{cid}/together/consent',headers=s,json={'approved':True}).json()['published'] is True
        created=client.post(f'/couples/{cid}/moments',headers=s,json={'title':'First anniversary','details':'Book somewhere special','moment_type':'milestone','planned_for':'2026-12-01T19:00:00Z'})
        assert created.status_code==200 and created.json()['completed'] is False
        assert client.patch(f"/couples/{cid}/moments/{created.json()['id']}",headers=a,json={'completed':True}).json()['completed'] is True
        assert client.get(f'/couples/{cid}/moments',headers=s).json()[0]['completed'] is True
        assert client.post(f'/couples/{cid}/moments',headers=j,json={'title':'Private access','moment_type':'date'}).status_code==404


def test_home_questionnaires_are_member_private_and_report_uses_only_shared_answers():
    with TestClient(app) as client:
        alex = client.post('/auth/dev-login', json={'email':'alex@twonest.test'}).json()['access_token']
        sam = client.post('/auth/dev-login', json={'email':'sam@twonest.test'}).json()['access_token']
        jamie = client.post('/auth/dev-login', json={'email':'jamie@twonest.test'}).json()['access_token']
        a = {'Authorization':f'Bearer {alex}'}; s = {'Authorization':f'Bearer {sam}'}; j = {'Authorization':f'Bearer {jamie}'}
        cid = client.post('/couples/invite', headers=a, json={'partner_email':'sam@twonest.test'}).json()['couple_id']
        client.post(f'/couples/{cid}/accept', headers=s)
        form = client.get(f'/couples/{cid}/home-questionnaire', headers=a).json()
        assert len(form['groups'][0]['questions']) == 10
        assert form['answers'] == []
        assert client.get(f'/couples/{cid}/home-questionnaire', headers=j).status_code == 404
        assert client.get(f'/couples/{cid}/living-report', headers=a).status_code == 403

        alex_answers = [
            {'question_id':'pets','value':'Happy to live with pets'},
            {'question_id':'cleanliness','value':2},
            {'question_id':'rent_budget','value':'£1,000–£1,500'},
            {'question_id':'neighbourhood_preferences','value':['Parks','Cafes','Culture']},
            {'question_id':'personal_space','value':1,'is_private':True},
        ]
        sam_answers = [
            {'question_id':'pets','value':'Happy to live with pets'},
            {'question_id':'cleanliness','value':4},
            {'question_id':'rent_budget','value':'£2,000–£2,500'},
            {'question_id':'neighbourhood_preferences','value':['Cafes','Parks','Restaurants']},
            {'question_id':'personal_space','value':5},
        ]
        assert client.put(f'/couples/{cid}/home-questionnaire/answers', headers=a, json={'answers':alex_answers}).status_code == 200
        assert client.put(f'/couples/{cid}/home-questionnaire/answers', headers=s, json={'answers':sam_answers}).status_code == 200
        alex_saved = client.get(f'/couples/{cid}/home-questionnaire', headers=a).json()['answers']
        assert next(row for row in alex_saved if row['question_id']=='personal_space')['is_private'] is True
        invalid = client.put(f'/couples/{cid}/home-questionnaire/answers', headers=a, json={'answers':[{'question_id':'marriage','value':'I hope to marry'}]})
        assert invalid.status_code == 422

        client.post(f'/couples/{cid}/home-mode', headers=a, json={'approved':True})
        client.post(f'/couples/{cid}/home-mode', headers=s, json={'approved':True})
        report = client.get(f'/couples/{cid}/living-report', headers=a)
        assert report.status_code == 200
        result = report.json()
        assert result['your_answer_count'] == 5 and result['partner_answer_count'] == 5
        assert result['shared_answer_count'] == 4
        assert any('pets' in row.lower() for row in result['strong_alignment'])
        assert any('cleanliness' in row.lower() for row in result['acceptable_differences'])
        assert any('rent' in row.lower() for row in result['discuss_early'])
        assert 'personal space' not in str(result).lower()
        assert 'Happy to live with pets' not in str(result)


def test_nest4_requires_all_four_approvals_and_portals_enforce_roles():
    with TestClient(app) as client:
        accounts={email:client.post('/auth/dev-login',json={'email':email}).json()['access_token'] for email in ('alex@twonest.test','sam@twonest.test','jamie@twonest.test','riley@twonest.test','partner@twonest.test','admin@twonest.test','moderator@twonest.test')}
        def h(email):return {'Authorization':f"Bearer {accounts[email]}"}
        c1=client.post('/couples/invite',headers=h('alex@twonest.test'),json={'partner_email':'sam@twonest.test'}).json()['couple_id'];client.post(f'/couples/{c1}/accept',headers=h('sam@twonest.test'))
        c2=client.post('/couples/invite',headers=h('jamie@twonest.test'),json={'partner_email':'riley@twonest.test'}).json()['couple_id'];client.post(f'/couples/{c2}/accept',headers=h('riley@twonest.test'))
        assert client.get('/couples/me',headers=h('alex@twonest.test')).json()[0]['status']=='active'
        assert client.get(f'/couples/{c1}/nest4-candidates',headers=h('alex@twonest.test')).status_code==403
        public_profile={'relationship_stage':'established','general_area':'East London','shared_interests':['cooking','travel'],'preferred_activities':['dinner'],'food_preferences':['vegetarian'],'social_energy':'balanced','children':'No children','pets':['cats'],'languages':['English'],'availability':['weekends'],'event_budget_min':15,'event_budget_max':60,'travel_interests':['city breaks']}
        for cid,owners in ((c1,('alex@twonest.test','sam@twonest.test')),(c2,('jamie@twonest.test','riley@twonest.test'))):
            assert client.put(f'/couples/{cid}/together',headers=h(owners[0]),json=public_profile).status_code==200
            for index, owner in enumerate(owners):
                publication=client.post(f'/couples/{cid}/together/consent',headers=h(owner),json={'approved':True}).json()
                assert publication['published'] is (index == len(owners)-1)
        assert len(client.get(f'/couples/{c1}/nest4-candidates',headers=h('alex@twonest.test')).json())==1
        assert client.get(f'/couples/{c1}/nest4-candidates',headers=h('alex@twonest.test')).json()[0]['alignment_reasons']
        match=client.post(f'/couples/{c1}/nest4/{c2}',headers=h('alex@twonest.test')).json()['match_id']
        for email in ('alex@twonest.test','sam@twonest.test','jamie@twonest.test'):
            result=client.post(f'/nest4/{match}/decision',headers=h(email),json={'approved':True}).json();assert result['group_chat_open'] is False
        assert client.get(f'/nest4/{match}/messages',headers=h('alex@twonest.test')).status_code==403
        result=client.post(f'/nest4/{match}/decision',headers=h('riley@twonest.test'),json={'approved':True}).json()
        assert result['status']=='matched' and result['group_chat_open'] is False
        assert client.get('/nest4',headers=h('alex@twonest.test')).json()[0]['status']=='matched'
        plan=client.post(f'/nest4/{match}/meeting-plans',headers=h('alex@twonest.test'),json={
            'title':'Dinner for four','venue':'The Neighbourhood Table','area':'Hackney',
            'starts_at':(datetime.now(timezone.utc)+timedelta(hours=1)).isoformat(),
        })
        assert plan.status_code==200 and plan.json()['status']=='proposed'
        assert client.post(f'/nest4/{match}/follow-up',headers=h('alex@twonest.test'),json={'decision':'meet_again'}).status_code==409
        for email in ('alex@twonest.test','sam@twonest.test','jamie@twonest.test','riley@twonest.test'):
            voted=client.post(f"/nest4/{match}/meeting-plans/{plan.json()['id']}/vote",headers=h(email),json={'attending':True})
            assert voted.status_code==200
        assert voted.json()['status']=='scheduled' and voted.json()['attending_count']==4
        assert client.post(f"/nest4/{match}/meeting-plans/{plan.json()['id']}/complete",headers=h('alex@twonest.test')).status_code==409
        db=SessionLocal()
        stored_plan=db.get(Nest4MeetingPlan,plan.json()['id'])
        stored_plan.starts_at=(datetime.now(timezone.utc)-timedelta(minutes=5)).isoformat()
        db.commit();db.close()
        held=client.post(f"/nest4/{match}/meeting-plans/{plan.json()['id']}/complete",headers=h('alex@twonest.test'))
        assert held.status_code==200 and held.json()['status']=='meeting_complete'
        for email in ('alex@twonest.test','sam@twonest.test','jamie@twonest.test'):
            choice=client.post(f'/nest4/{match}/follow-up',headers=h(email),json={'decision':'meet_again'})
            assert choice.status_code==200 and choice.json()['group_chat_open'] is False
        private=client.get(f'/nest4/{match}/follow-up',headers=h('alex@twonest.test')).json()
        assert private['your_decision']=='meet_again' and private['decisions_received']==3
        assert client.post(f'/nest4/{match}/messages',headers=h('alex@twonest.test'),json={'body':'Lovely to meet all of you'}).status_code==403
        connected=client.post(f'/nest4/{match}/follow-up',headers=h('riley@twonest.test'),json={'decision':'invite_activity'})
        assert connected.json()['status']=='connected' and connected.json()['group_chat_open'] is True
        message=client.post(f'/nest4/{match}/messages',headers=h('alex@twonest.test'),json={'body':'Lovely to meet all of you'})
        assert message.status_code==200
        assert client.get(f'/nest4/{match}/messages',headers=h('sam@twonest.test')).json()[0]['body']=='Lovely to meet all of you'
        assert client.get(f'/nest4/{match}/messages',headers=h('admin@twonest.test')).status_code==404
        assert client.get('/nest4',headers=h('alex@twonest.test')).json()[0]['status']=='connected'
        assert client.get('/admin/operations',headers=h('partner@twonest.test')).status_code==403
        assert client.get('/partner/bookings',headers=h('admin@twonest.test')).status_code==200
        assert client.get('/admin/operations',headers=h('admin@twonest.test')).status_code==200
        report=client.post('/safety/reports',headers=h('alex@twonest.test'),json={'subject_id':'member-sam','category':'uncomfortable_contact','details':'I would like a moderator to review this interaction.'})
        assert report.status_code==200 and report.json()['private'] is True
        assert len(client.get('/admin/safety-reports',headers=h('moderator@twonest.test')).json())==1


def test_member_can_save_private_onboarding_and_discovery_preferences():
    with TestClient(app) as client:
        token = client.post('/auth/dev-login', json={'email':'alex@twonest.test'}).json()['access_token']
        headers = {'Authorization': f'Bearer {token}'}
        initial = client.get('/onboarding', headers=headers)
        assert initial.status_code == 200
        assert initial.json()['first_name'] == 'Alex'

        saved = client.patch('/onboarding', headers=headers, json={
            'date_of_birth': '1992-05-10',
            'pronouns': 'she/her',
            'intention': 'life_partner',
            'area': 'Hackney',
            'search_radius_km': 35,
            'languages': ['English', 'Spanish'],
            'availability': ['weekends'],
            'dietary_requirements': ['vegetarian'],
            'event_budget_min': 15,
            'event_budget_max': 60,
            'interests': ['cooking', 'travel'],
        })
        assert saved.status_code == 200
        assert saved.json()['complete'] is True
        assert saved.json()['dating_preferences'] == []
        assert saved.json()['languages'] == ['English', 'Spanish']
        assert saved.json()['event_budget_min'] == 15
        assert client.get('/me', headers=headers).json()['profile']['area'] == 'Hackney'

        underage = client.patch('/onboarding', headers=headers, json={'date_of_birth':'2012-01-01'})
        assert underage.status_code == 422


def test_compatibility_questionnaire_is_validated_private_and_scored_for_discovery():
    with TestClient(app) as client:
        alex = client.post('/auth/dev-login', json={'email':'alex@twonest.test'}).json()['access_token']
        headers = {'Authorization': f'Bearer {alex}'}
        form = client.get('/questionnaire', headers=headers).json()
        assert len(form['groups']) >= 4
        assert len(form['answers']) >= 20

        saved = client.put('/questionnaire/answers', headers=headers, json={'answers':[
            {'question_id':'marriage','value':'Open to it','importance':3,'deal_breaker':True,'is_private':True}
        ]})
        assert saved.status_code == 200
        answer = next(row for row in client.get('/questionnaire', headers=headers).json()['answers'] if row['question_id'] == 'marriage')
        assert answer['is_private'] is True and answer['deal_breaker'] is True
        invalid = client.put('/questionnaire/answers', headers=headers, json={'answers':[{'question_id':'marriage','value':'Wrong value'}]})
        assert invalid.status_code == 422

        client.patch('/onboarding', headers=headers, json={'intention':'serious_dating'})
        recommendations = client.post('/introductions/refresh', headers=headers)
        assert recommendations.status_code == 200
        assert recommendations.json()['created_count'] == 2
        current = client.get('/introductions', headers=headers).json()
        assert all(row['score'] >= 55 and row['reasons'] for row in current)
        assert all('compatibility_answers' not in str(row['candidate']) for row in current)
        capped = client.post('/introductions/refresh', headers=headers)
        assert capped.json()['created_count'] == 0


def test_block_removes_recommendations_and_closes_the_conversation():
    with TestClient(app) as client:
        alex = client.post('/auth/dev-login', json={'email':'alex@twonest.test'}).json()['access_token']
        sam = client.post('/auth/dev-login', json={'email':'sam@twonest.test'}).json()['access_token']
        alex_headers = {'Authorization': f'Bearer {alex}'}
        sam_headers = {'Authorization': f'Bearer {sam}'}
        existing_chat = client.get('/conversations', headers=alex_headers).json()[0]
        assert existing_chat['with'] == 'Sam'
        assert any(row['candidate']['id'] == 'member-sam' for row in client.get('/introductions', headers=alex_headers).json())

        blocked = client.post('/members/member-sam/block', headers=alex_headers)
        assert blocked.status_code == 200 and blocked.json()['blocked'] is True
        assert all(row['candidate']['id'] != 'member-sam' for row in client.get('/introductions', headers=alex_headers).json())
        assert all(row['candidate']['id'] != 'member-alex' for row in client.get('/introductions', headers=sam_headers).json())
        assert client.get('/conversations', headers=alex_headers).json() == []
        assert client.post(f"/conversations/{existing_chat['id']}/messages", headers=alex_headers, json={'body':'Hello again'}).status_code == 404
        assert client.delete('/members/member-sam/block', headers=alex_headers).json()['blocked'] is False


def test_circle_four_week_prompt_chat_and_meeting_plan_flow(tmp_path, monkeypatch):
    monkeypatch.setenv('TWONEST_CIRCLE_MEDIA_DIR', str(tmp_path))
    with TestClient(app) as client:
        tokens = {email:client.post('/auth/dev-login', json={'email':email}).json()['access_token'] for email in ('alex@twonest.test','sam@twonest.test','admin@twonest.test')}
        alex_headers = {'Authorization':f"Bearer {tokens['alex@twonest.test']}"}
        admin_headers = {'Authorization':f"Bearer {tokens['admin@twonest.test']}"}
        assert client.get('/circles',headers=admin_headers).status_code == 403
        circles = client.get('/circles',headers=alex_headers).json()
        circle = next(row for row in circles if row['id']=='circle-east-london')
        assert circle['week'] == 3 and circle['joined'] is False
        assert client.get('/circles/circle-east-london',headers=alex_headers).status_code == 404

        joined = client.post('/circles/circle-east-london/join',headers=alex_headers)
        assert joined.status_code == 200 and joined.json()['joined'] is True
        detail = client.get('/circles/circle-east-london',headers=alex_headers).json()
        assert detail['current_prompt']['week'] == 3 and len(detail['members']) == 4
        response = client.post('/circles/circle-east-london/responses',headers=alex_headers,json={'selected_options':['Coffee and a walk','Museum or gallery']})
        assert response.status_code == 200 and response.json()['submitted'] is True
        polled = client.get('/circles/circle-east-london',headers=alex_headers).json()
        assert polled['current_prompt']['poll_counts']['Coffee and a walk'] == 1
        assert polled['my_response']['selected_options'] == ['Coffee and a walk','Museum or gallery']
        assert client.post('/circles/circle-east-london/responses',headers=alex_headers,json={'selected_options':['a private phone number']}).status_code == 422
        prompt_id = detail['current_prompt']['id']
        audio = b'\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00'
        voice = client.post(f'/circles/circle-east-london/prompts/{prompt_id}/voice-note',headers={**alex_headers,'Content-Type':'audio/mp4'},content=audio)
        assert voice.status_code == 200 and voice.json()['has_voice_note'] is True
        asset_key = voice.json()['voice_asset_key']
        assert client.get(f'/circles/circle-east-london/voice-notes/{asset_key}',headers=alex_headers).content == audio
        assert client.get(f'/circles/circle-east-london/voice-notes/{asset_key}',headers=admin_headers).status_code == 404
        message = client.post('/circles/circle-east-london/messages',headers=alex_headers,json={'body':'Would Sunday afternoon work for everyone?'})
        assert message.status_code == 200
        assert 'Sunday afternoon' in client.get('/circles/circle-east-london',headers=alex_headers).json()['messages'][-1]['body']

        plan = client.post('/circles/circle-east-london/meeting-plans',headers=alex_headers,json={'title':'Coffee and a walk','venue':'Victoria Park Cafe','area':'Hackney','starts_at':'2099-06-12T14:00:00Z'})
        assert plan.status_code == 200
        vote = client.post(f"/circles/circle-east-london/meeting-plans/{plan.json()['id']}/vote",headers=alex_headers,json={'attending':True})
        assert vote.status_code == 200 and vote.json()['yes_count'] == 1
        assert client.post('/circles/circle-east-london/leave',headers=alex_headers).json()['left'] is True
        assert client.get('/circles/circle-east-london',headers=alex_headers).status_code == 404
