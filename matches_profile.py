import json

# analyze the json data
# generate 2 tables
# data/players.json
# data/matches_profile.json

players = {} # id -> (name, sex, nation)
matches = []

# the following fields will be extracted to matches list
# vw_matches___id_raw -> id
# vw_matches___tournament_id_raw -> event_id
# vw_matches___player_a_id_raw -> player_a_id
# vw_matches___player_b_id_raw -> player_b_id
# vw_matches___player_x_id_raw -> player_x_id
# vw_matches___player_y_id_raw -> player_y_id
# vw_matches___stage_raw -> stage
# vw_matches___round_raw -> round
# vw_matches___res_raw -> result
# vw_matches___games_raw -> games

# the following fields will refresh the players map
# vw_matches___name_a_raw -> player_a_name
# vw_matches___name_b_raw -> player_b_name
# vw_matches___name_x_raw -> player_x_name
# vw_matches___name_y_raw -> player_y_name

def update_player(id, name, event):
    if id is not None:
        sex = 'U'
        if 'W' in event or 'G' in event:
            sex = 'W'
        elif 'M' in event or 'B' in event:
            sex = 'M'
        try:
            nation = name.split('(')[-1].split(')')[0].strip()
        except:
            nation = ''
        if id not in players:
            name = name.split('(')[0].strip()
            players[id] = [name, sex, nation]
        else:
            if sex != 'U':
                players[id][1] = sex
            if nation != '':
                players[id][2] = nation

# record the mixed double
mixed_double = []

file_count = 7342
for i in range(file_count):
    json_file = 'matches/matches_{}.json'.format(i)
    with open(json_file, 'r') as f:
        data = json.load(f)
        for match in data[0]:
            id = match['vw_matches___id_raw']
            event_id = match['vw_matches___tournament_id_raw']
            player_a_id = match['vw_matches___player_a_id_raw']
            player_b_id = match['vw_matches___player_b_id_raw']
            player_x_id = match['vw_matches___player_x_id_raw']
            player_y_id = match['vw_matches___player_y_id_raw']
            stage = match['vw_matches___stage_raw']
            round = match['vw_matches___round_raw']
            result = match['vw_matches___res_raw']
            games = match['vw_matches___games_raw']
            player_a_name = match['vw_matches___name_a_raw']
            player_b_name = match['vw_matches___name_b_raw']
            player_x_name = match['vw_matches___name_x_raw']
            player_y_name = match['vw_matches___name_y_raw']
            event = match['vw_matches___event_raw']
            update_player(player_a_id, player_a_name, event)
            update_player(player_b_id, player_b_name, event)
            update_player(player_x_id, player_x_name, event)
            update_player(player_y_id, player_y_name, event)
            if 'X' in event and 'XT' not in event:
                mixed_double.append((player_a_id, player_b_id))
                mixed_double.append((player_x_id, player_y_id))
            matches.append({
                'id': id,
                'event_id': event_id,
                'player_a_id': player_a_id,
                'player_b_id': player_b_id,
                'player_x_id': player_x_id,
                'player_y_id': player_y_id,
                'event': event,
                'stage': stage,
                'round': round,
                'result': result,
                'games': games
            })
    print('analyzed {}'.format(json_file))

# use mixed_double to infer the sex of players
def reverse_sex(sex):
    if sex == 'W':
        return 'M'
    else:
        return 'W'

mixed_double_count = 0
while mixed_double_count != len(mixed_double):
    mixed_double_next = []
    for d in mixed_double:
        if d[0] is None or d[1] is None:
            continue
        if players[d[0]][1] == 'U' and players[d[1]][1] != 'U':
            players[d[0]][1] = reverse_sex(players[d[1]][1])
        if players[d[1]][1] == 'U' and players[d[0]][1] != 'U':
            players[d[1]][1] = reverse_sex(players[d[0]][1])
        if players[d[0]][1] == 'U' and players[d[1]][1] == 'U':
            mixed_double_next.append(d)
    mixed_double_count = len(mixed_double)
    mixed_double = mixed_double_next

# save the data
players_json = []
for id in players:
    players_json.append({
        'id': id,
        'name': players[id][0],
        'sex': players[id][1],
        'nation': players[id][2]
    })
with open('data/players.json', 'w') as f:
    json.dump(players_json, f)

with open('data/matches_profile.json', 'w') as f:
    json.dump(matches, f)

