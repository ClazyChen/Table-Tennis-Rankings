# analyze events' profile: types

import json

# load the profile
with open('events/events_profile.json', 'r', encoding='utf-8') as f:
    profile = json.load(f)

# select types
types = []
type_events = {}

for event in profile:
    type = r'{}'.format(event['type'])
    if type not in types:
        types.append(type)
        type_events[type] = []
    type_events[type].append('{}, {}'.format(event['name'], event['year']))

# output the result
with open('events/events_types.txt', 'w', encoding='utf-8') as f:
    for t in types:
        f.write('type = {}\n'.format(t))
        for event in type_events[t]:
            f.write('  {}\n'.format(event))
