import json

# analyze data/matches_profile.json
# list all (round, stage) pairs

pairs = []
events = []

with open('data/matches_profile.json', 'r') as f:
    matches_json = json.load(f)
    for match in matches_json:
        stage = match['stage']
        round = match['round']
        event = match['event']
        if stage is None:
            stage = "-"
        if round is None:
            round = "-"
        if event is None:
            event = "-"
        if event not in events:
            events.append(event)
        if (stage, round) not in pairs:
            pairs.append((stage, round))

pairs.sort()
events.sort()

print(pairs)
print(events)