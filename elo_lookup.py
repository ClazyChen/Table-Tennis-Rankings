import json
from elo_preparation import date2int

date = '2024-02-16'
date = date2int(date)
target_event_id = 2751

def read_elo(game_type):
    with open('data/elo_report_{}.json'.format(game_type), 'r') as f:
        elo_report = json.load(f)

    # analyze the elo report to get the elo of the player at the given date
    elo = {}
    for item in elo_report:
        id = item['id']
        name = item['name']
        nation = item['nation']
        rating = 0
        for rat in item['rating']:
            d, r = rat[0], rat[1]
            if d > date:
                break
            rating = r
        if item['rating'][-1][0] + 365 < date:
            continue
        elo[id] = {
            'name': name,
            'nation': nation,
            'rating': rating
        }

    # calculate the ranking
    ranking = []
    for name, item in elo.items():
        ranking.append((name, item['rating']))
    ranking.sort(key=lambda x: x[1], reverse=True)
    for index, r in enumerate(ranking):
        elo[r[0]]['ranking'] = index + 1
    
    print('read elo_report_{}.json'.format(game_type))

    return elo

elo_reports = {
    'MS': read_elo('MS'),
    'WS': read_elo('WS'),
}

# load the players data
players = {}
with open('data/players.json', 'r') as f:
    players_json = json.load(f)
    for player in players_json:
        if player['sex'] == 'U':
            continue
        players[player['id']] = [player['name'], player['sex']]

lookup_result = {
    'MS': [],
    'WS': []
}

def get_result(result):
    # result = 'X - Y'
    # delta = X - Y
    result = result.split('-')
    X = int(result[0].strip())
    Y = int(result[1].strip())
    return X - Y

# load the matches data
total_matches = {'MS': 0, 'WS': 0}
correct_matches = {'MS': 0, 'WS': 0}
with open('data/matches_profile.json', 'r') as f:
    matches_json = json.load(f)
    for match in matches_json:
        event_id = match['event_id']
        if event_id != target_event_id:
            continue
        player_a_id = match['player_a_id']
        player_b_id = match['player_b_id']
        player_x_id = match['player_x_id']
        player_y_id = match['player_y_id']
        if player_a_id is None or player_x_id is None:
            continue
        if player_b_id is not None or player_y_id is not None:
            continue
        if player_a_id not in players or player_x_id not in players:
            continue
        sex = players[player_a_id][1]
        game_type = sex + 'S'
        if player_a_id not in elo_reports[game_type] or player_x_id not in elo_reports[game_type]:
            continue
        result = match['result']
        elo_a_item = elo_reports[game_type][player_a_id]
        elo_x_item = elo_reports[game_type][player_x_id]
        total_matches[game_type] += 1
        s = '{} (#{}) {} {} (#{})'.format(elo_a_item['name'], elo_a_item['ranking'], result, elo_x_item['name'], elo_x_item['ranking'])
        delta = get_result(result)
        ranking_delta = elo_a_item['rating'] - elo_x_item['rating']
        if delta * ranking_delta > 0:
            correct_matches[game_type] += 1
            s += ' correct'
        else:
            s += ' wrong'
        lookup_result[game_type].append(s)

for game_type in ['MS', 'WS']:
    if total_matches[game_type] == 0:
        continue
    print('{} : {} / {} ( {} % )'.format(game_type, correct_matches[game_type], total_matches[game_type], correct_matches[game_type] / total_matches[game_type] * 100))
    for s in lookup_result[game_type]:
        print(s)
