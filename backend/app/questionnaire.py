"""Versioned, server-owned compatibility questionnaire definitions."""

QUESTION_GROUPS = [
    {
        "id": "goals", "title": "The future you want",
        "questions": [
            {"id": "relationship_timeline", "category": "goals", "prompt": "When would you hope to build a committed relationship?", "response_type": "single_select", "options": ["Soon, with the right person", "Within 1–2 years", "I’m open to seeing how it grows", "Not sure yet"]},
            {"id": "marriage", "category": "goals", "prompt": "How do you feel about marriage?", "response_type": "single_select", "options": ["I hope to marry", "Open to it", "Prefer not to marry", "Not sure"]},
            {"id": "children", "category": "goals", "prompt": "What feels right for you around children?", "response_type": "single_select", "options": ["Want children", "Don’t want children", "Open to either", "Already have children", "Prefer not to say"]},
            {"id": "family_involvement", "category": "values", "prompt": "How involved would you like family to be in your life?", "response_type": "scale", "minimum": 1, "maximum": 5},
            {"id": "what_im_building", "category": "goals", "prompt": "What are you building toward?", "response_type": "free_text", "maximum_length": 500},
        ],
    },
    {
        "id": "values", "title": "Values and direction",
        "questions": [
            {"id": "religion_and_spirituality", "category": "values", "prompt": "What place do religion or spirituality have in your life?", "response_type": "single_select", "options": ["A central part", "Somewhat important", "Not a major part", "Prefer not to say"]},
            {"id": "culture_and_tradition", "category": "values", "prompt": "How important are cultural traditions in your home?", "response_type": "scale", "minimum": 1, "maximum": 5},
            {"id": "career_and_ambition", "category": "values", "prompt": "How does career fit into the life you want?", "response_type": "single_select", "options": ["A major focus", "Important but balanced", "A steady part of life", "I’m figuring it out"]},
            {"id": "spending_and_saving", "category": "values", "prompt": "Which best describes your approach to money?", "response_type": "single_select", "options": ["Save for the future", "Balance saving and enjoying", "Enjoy experiences now", "Prefer to discuss privately"]},
        ],
    },
    {
        "id": "communication", "title": "How you connect",
        "questions": [
            {"id": "communication_style", "category": "communication", "prompt": "How do you prefer to communicate when something matters?", "response_type": "single_select", "options": ["Talk it through right away", "Take time, then talk", "Write my thoughts first", "Depends on the situation"]},
            {"id": "conflict_style", "category": "communication", "prompt": "When there’s a disagreement, what helps you most?", "response_type": "single_select", "options": ["Calm direct conversation", "A little time and space", "Finding a practical compromise", "Reassurance and empathy"]},
            {"id": "social_energy", "category": "lifestyle", "prompt": "What kind of social rhythm feels best?", "response_type": "scale", "minimum": 1, "maximum": 5},
        ],
    },
    {
        "id": "lifestyle", "title": "Everyday life",
        "questions": [
            {"id": "weekend_interests", "category": "interests", "prompt": "Which things would you enjoy sharing?", "response_type": "multiple_select", "options": ["Cooking", "Museums and culture", "Travel", "Books", "Running or fitness", "Live music", "Quiet weekends", "Trying new restaurants", "Outdoors", "Games"]},
            {"id": "travel_style", "category": "lifestyle", "prompt": "What kind of travel do you enjoy?", "response_type": "single_select", "options": ["Planned trips", "Spontaneous weekends", "Slow stays in one place", "A mix of everything", "I don’t travel much"]},
            {"id": "food_and_drink", "category": "lifestyle", "prompt": "What sounds like a lovely evening?", "response_type": "single_select", "options": ["Cooking at home", "A favourite neighbourhood spot", "Trying somewhere new", "A relaxed drink or coffee", "A mix"]},
            {"id": "fitness", "category": "lifestyle", "prompt": "How does movement fit into your routine?", "response_type": "single_select", "options": ["Most days", "A few times a week", "Now and then", "It’s not really my thing"]},
            {"id": "smoking", "category": "lifestyle", "prompt": "Which best describes smoking in your life?", "response_type": "single_select", "options": ["Never", "Occasionally", "Regularly", "Prefer to discuss privately"]},
            {"id": "alcohol", "category": "lifestyle", "prompt": "What is your relationship with alcohol?", "response_type": "single_select", "options": ["Don’t drink", "Occasionally", "Socially", "Prefer to discuss privately"]},
            {"id": "pets", "category": "home_life", "prompt": "How do pets fit into your future home?", "response_type": "single_select", "options": ["I have or want pets", "Happy to live with pets", "Prefer a pet-free home", "Not sure"]},
            {"id": "sleep_schedule", "category": "home_life", "prompt": "What is your usual rhythm?", "response_type": "single_select", "options": ["Early bird", "Night owl", "Somewhere in between", "It varies"]},
            {"id": "cleanliness", "category": "home_life", "prompt": "What feels comfortable for a shared home?", "response_type": "scale", "minimum": 1, "maximum": 5},
            {"id": "cooking_at_home", "category": "home_life", "prompt": "How often do you like cooking at home?", "response_type": "single_select", "options": ["Most days", "A few times a week", "Occasionally", "Rarely"]},
            {"id": "working_from_home", "category": "home_life", "prompt": "How often do you work or study from home?", "response_type": "single_select", "options": ["Most days", "A few days a week", "Occasionally", "Rarely"]},
            {"id": "guests_at_home", "category": "home_life", "prompt": "How do you feel about having guests over?", "response_type": "scale", "minimum": 1, "maximum": 5},
            {"id": "personal_space", "category": "home_life", "prompt": "How much independent time helps you recharge?", "response_type": "scale", "minimum": 1, "maximum": 5},
            {"id": "neighbourhood_preferences", "category": "home_life", "prompt": "What would you love nearby? Rank your top choices.", "response_type": "ranking", "options": ["Parks", "Cafes", "Restaurants", "Public transport", "Quiet streets", "Culture", "Shops", "Fitness"]},
            {"id": "rent_budget", "category": "home_life", "prompt": "What monthly rent range feels comfortable for you?", "response_type": "single_select", "options": ["Under £1,000", "£1,000–£1,500", "£1,500–£2,000", "£2,000–£2,500", "Over £2,500", "Prefer to discuss privately"]},
            {"id": "moving_timeline", "category": "home_life", "prompt": "When might you want to share a home with a partner?", "response_type": "single_select", "options": ["Within a year", "In 1–2 years", "Further in the future", "Only when it feels right", "Not sure"]},
        ],
    },
]

QUESTION_BY_ID = {
    question["id"]: question
    for group in QUESTION_GROUPS
    for question in group["questions"]
}
