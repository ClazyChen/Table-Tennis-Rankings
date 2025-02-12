import json
import datetime
import scipy.stats as stats

def weight_calc(w, l):
    norm_dist = stats.norm(loc=0, scale=2/(w ** 0.5))
    F = norm_dist.cdf
    return 1 - 2*F(-(w-l)/2)

# 预先计算好所有可能的权重
weight_map = {}
for w in range(1, 10):
    for l in range(0, w):
        weight_map[(w, l)] = weight_calc(w, l)

# analyze the json data
# 1. remove players whose sex is unknown
# 2. read the events data, get event_id -> end_date data
# 3. read the matches data, generate: (for MS/WS/MD/WD/XD)
#    player_a/b/x/y_id, where b/y works for doubles
#    date (use the end_date of the event)
#    weight (coefficient)
# 4. output the result to data/elo_preparation.json

# game weight:
# BO7 4 : 0     31 / 32
#     4 : 1     57 / 64
#     4 : 2     99 / 128
#     4 : 3     163 / 256
# BO5 3 : 0     15 / 16
#     3 : 1     13 / 16
#     3 : 2     21 / 32
# BO3 2 : 0     7 / 8
#     2 : 1     11 / 16
# BO1 1 : 0     3 / 4
# tie           0

# load the players data
players = {}
with open('data/players.json', 'r') as f:
    players_json = json.load(f)
    for player in players_json:
        if player['sex'] == 'U':
            continue
        players[player['id']] = [player['name'], player['sex']]

# convert date (YYYY-MM-DD) to int to calculate delta days
def date2int(date):
    # make date1 - date2 = the number of days between date1 and date2
    date1 = datetime.datetime.strptime(date, '%Y-%m-%d')
    date2 = datetime.datetime.strptime('1970-01-01', '%Y-%m-%d')
    return (date1 - date2).days

# load the events data
events = {}
events_coef = {}
with open('events/events_profile.json', 'r') as f:
    events_json = json.load(f)
    for event in events_json:
        try:
            events[event['id']] = date2int(event['end'])
        except:
            # 2012 ITTF Oceania Cup, Suva (FIJ): 2012-06-03 - 2012-06-08
            events[event['id']] = date2int('2012-06-08')
        events_coef[event['id']] = event['coefficient'] 

# convert the result of a game to delta
def result2weight(result):
    # result = 'X - Y'
    # delta = X - Y
    # game = max(X, Y) * 2 - 1
    result = result.split('-')
    X = int(result[0].strip())
    Y = int(result[1].strip())
    delta = X - Y
    abs_delta = abs(delta)
    # game = max(X, Y) * 2 - 1
    if delta == 0:
        return 0
    sgn_delta = delta / abs_delta
    W = max(X, Y)
    L = min(X, Y)
    return weight_map[(W, L)] * sgn_delta
    # if game == 1:
    #     return 0.383 * sgn_delta
    # if game == 3:
    #     if abs_delta == 1:
    #         return 11 / 16 * sgn_delta
    #     else:
    #         return 7 / 8 * sgn_delta
    # if game == 5:
    #     if abs_delta == 1:
    #         return 21 / 32 * sgn_delta
    #     elif abs_delta == 2:
    #         return 13 / 16 * sgn_delta
    #     else:
    #         return 15 / 16 * sgn_delta
    # # other conditions 
    # if abs_delta == 1:
    #     return 163 / 256 * sgn_delta
    # elif abs_delta == 2:
    #     return 99 / 128 * sgn_delta
    # elif abs_delta == 3:
    #     return 57 / 64 * sgn_delta
    # elif abs_delta == 4:
    #     return 31 / 32 * sgn_delta
    # else:
    #     return sgn_delta

# load the matches data
matches = {
    'MS': [],
    'WS': [],
    'MD': [],
    'WD': [],
    'XD': []
}
with open('data/matches_profile.json', 'r') as f:
    matches_json = json.load(f)
    for match in matches_json:
        id = match['id']
        date = events[match['event_id']]
        player_a_id = match['player_a_id']
        player_b_id = match['player_b_id']
        player_x_id = match['player_x_id']
        player_y_id = match['player_y_id']
        stage = match['stage']
        event = match['event']
        event_coef = events_coef[match['event_id']]
        result_weight = result2weight(match['result'])
        weight = result_weight * event_coef
        if 'U' in event:
            # 青年赛
            weight *= 0.01
        if stage is None or not ('Main' in stage or 'Position' in stage):
            # 资格赛
            weight *= 0.8
        if player_b_id is None:
            if player_a_id is None or player_x_id is None:
                # invalid match 退赛
                continue
            if player_a_id not in players or player_x_id not in players:
                # 不知名选手
                continue
            j = {
                'id': id,
                'player_a_id': player_a_id,
                'player_x_id': player_x_id,
                'date': date,
                'weight': weight,
                'result': result_weight
            }
            if players[player_a_id][1] == 'M':
                matches['MS'].append(j)
            else:
                matches['WS'].append(j)
        else:
            if player_a_id is None or player_x_id is None or player_y_id is None:
                # invalid match 退赛
                continue
            if player_a_id not in players or player_b_id not in players or player_x_id not in players or player_y_id not in players:
                # 不知名选手
                continue
            j = {
                'id': id,
                'player_a_id': player_a_id,
                'player_b_id': player_b_id,
                'player_x_id': player_x_id,
                'player_y_id': player_y_id,
                'date': date,
                'weight': weight,
                'result': result_weight
            }
            if players[player_a_id][1] == 'M':
                if players[player_b_id][1] == 'M':
                    matches['MD'].append(j)
                else:
                    matches['XD'].append(j)
            else:
                if players[player_b_id][1] == 'W':
                    matches['WD'].append(j)
                else:
                    matches['XD'].append(j)

# output the result
for key in matches:
    # matches[key] sorted by date
    matches[key].sort(key=lambda x: (x['date'], x['id']))
    with open('data/elo_preparation_{}.json'.format(key), 'w') as f:
        json.dump(matches[key], f)
