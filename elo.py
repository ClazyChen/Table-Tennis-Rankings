# use elo algorithm to analyze the data

import os
import json
import datetime
from prettytable import PrettyTable

# for every match:
# 1. new player: base rating = 1500
#    known player: base rating = current rating
#    rating = base rating + weight * (result - expected result)
#    expected result = 1 / (1 + 10 ^ ((rating_a - rating_b) / 400))
# 2. update the rating of the player

# if inactive_test is enabled:
# 3. when r < r' < the opponent's rating or r > r' > the opponent's rating:
#    and the player is inactive (no match for 64 days)
#    r'' = r' + (the opponent's rating - r') * (1 - (1 - x / 365) ^ 2)

# update the world ranking list every event
# only players has more than 10 matches will be ranked

centered = True
inactive_test = True
default_rating = 1500
ceil_rating = 3500
ranking_least_games = 10
game_type = 'MS' # MS, WS, MD, WD, XD
bias = 40
d = 640
diameter_center = 800
diameter_delta = 400

# load the players data
players = {}
players_nation = {}
with open('data/players.json', 'r') as f:
    players_json = json.load(f)
    for player in players_json:
        if player['sex'] == 'U':
            continue
        players[player['id']] = player['name']
        players_nation[player['id']] = player['nation']

elo_report = {}

# convert date
def convert_date(date):
    # date is the day number from 1970-01-01
    # convert date to datetime
    date = datetime.datetime.strptime('1970-01-01', '%Y-%m-%d') + datetime.timedelta(days=date)
    return date.strftime('%Y-%m-%d')

players_ratings = {} # id -> [rating, cur match date, last match date, match count]

# load the matches data
with open('data/elo_preparation_{}.json'.format(game_type), 'r') as f:
    matches = json.load(f)

cur_date = 0

# check if the player is in the list
def check_player(id):
    if id not in players_ratings:
        players_ratings[id] = [default_rating, cur_date, 0, 0]
        # first match
        elo_report[id] = {
            'name': players[id],
            'nation': players_nation[id],
            'rating': { cur_date : default_rating }
        }
    elif cur_date != players_ratings[id][1]:
        players_ratings[id][2] = players_ratings[id][1]
        players_ratings[id][1] = cur_date

total_matches = 0
correct_matches = 0
timestone = datetime.datetime.strptime('2018-01-01', '%Y-%m-%d') - datetime.datetime.strptime('1970-01-01', '%Y-%m-%d')
timestone = timestone.days
def check_result(id1, id2, weight):
    global total_matches, correct_matches
    if cur_date < timestone:
        return
    if weight == 0:
        return
    if id1 not in players_ratings or id2 not in players_ratings:
        return
    if players_ratings[id1][3] < ranking_least_games or players_ratings[id2][3] < ranking_least_games:
        return
    total_matches += 1
    r1 = players_ratings[id1][0]
    r2 = players_ratings[id2][0]
    if (r1 > r2 and weight > 0) or (r1 < r2 and weight < 0):
        correct_matches += 1

# update elo
def update_elo(id1, id2, weight, result):
    r1 = players_ratings[id1][0]
    r2 = players_ratings[id2][0]
    e1 = 1 / (1 + 10 ** ((r1 - r2) / d))
    e2 = 1 / (1 + 10 ** ((r2 - r1) / d))
    a1 = (1 if weight > 0 else 0)
    if weight == 0:
        a1 = 0.5
    a2 = 1 - a1
    w = abs(weight)
    if weight == 0:
        w = 0.5
    w *= bias

    # 向心力，使得rating更加集中
    delta1 = w * (a1 - e1)
    delta2 = w * (a2 - e2)
    center_coef1 = 1
    center_coef2 = 1
    center_exp = 1
    delta_exp = 1
    if centered:
        if delta1 < 0:
            center_coef1 *= (1 - 1 / (1 + 10 ** ((r1 - default_rating) / diameter_center))) ** center_exp * 2
            center_coef1 *= (1 - 1 / (1 + 10 ** ((r1 - r2) / diameter_delta))) ** delta_exp * 2
        else:
            center_coef1 *= (1 - 1 / (1 + 10 ** ((ceil_rating - r1) / diameter_center))) ** center_exp * 2
            center_coef1 *= (1 - 1 / (1 + 10 ** ((r2 - r1) / diameter_delta))) ** delta_exp * 2
        if delta2 < 0:
            center_coef2 *= (1 - 1 / (1 + 10 ** ((r2 - default_rating) / diameter_center))) ** center_exp * 2
            center_coef2 *= (1 - 1 / (1 + 10 ** ((r2 - r1) / diameter_delta))) ** delta_exp * 2
        else:
            center_coef2 *= (1 - 1 / (1 + 10 ** ((ceil_rating - r2) / diameter_center))) ** center_exp * 2
            center_coef2 *= (1 - 1 / (1 + 10 ** ((r1 - r2) / diameter_delta))) ** delta_exp * 2
    else:
        center_coef1 = 4
        center_coef2 = 4

    delta1 *= center_coef1
    delta2 *= center_coef2

    r11 = r1 + delta1
    r21 = r2 + delta2
    t = 1.5
    inc_coef = 2 / 3 / 4 ** t
    dec_coef = 0
    exp_coef = 7
    exp_coef2 = 7 * 10
    coef_d1 = 1 # (1 - (1 - min(1, d1 / 365)) ** (exp_coef + exp_coef2 * players_ratings[id1][3])) 
    coef_d2 = 1 # (1 - (1 - min(1, d2 / 365)) ** (exp_coef + exp_coef2 * players_ratings[id2][3]))
    if inactive_test:
        d1 = players_ratings[id1][1] - players_ratings[id1][2]
        d2 = players_ratings[id2][1] - players_ratings[id2][2]
        if (r1 < r11 and r11 < r2):
            r11 = r11 + inc_coef * (r2 - r11) * coef_d1 * center_coef1 ** t
        elif (r1 > r11 and r11 > r2):
            r11 = r11 + dec_coef * (r2 - r11) * coef_d1 * center_coef1 ** t
        if (r1 > r21 and r21 > r2):
            r21 = r21 + inc_coef * (r2 - r21) * coef_d2 * center_coef2 ** t
        elif (r1 < r21 and r21 < r2):
            r21 = r21 + dec_coef * (r2 - r21) * coef_d2 * center_coef2 ** t
    return r11, r21

def sort_ratings():
    temp = []
    for id, player in players_ratings.items():
        if player[3] >= ranking_least_games and (player[1] >= cur_date - (365 if 'S' in game_type else 730) or (id in player_last_match and player_last_match[id] > cur_date)):
            if 'S' in game_type:
                temp.append((player[0], players[id], players_nation[id], id))
            else:
                if players_nation[id[0]] == players_nation[id[1]]:
                    temp_nation = players_nation[id[0]]
                else:
                    temp_nation = players_nation[id[0]] + ' / ' + players_nation[id[1]]
                temp.append((player[0], players[id[0]] + ' / ' + players[id[1]], temp_nation, id))
    temp.sort(reverse=True)
    return temp

def print_rankings():
    tb = PrettyTable()
    tb.field_names = ['Ranking', 'Name', 'Nation', 'ELO Rating']
    temp = sort_ratings()
    for i in range(32):
        if i < len(temp):
            tb.add_row([i+1, temp[i][1], temp[i][2], temp[i][0]])
    print(tb)
    input("tap to continue")

# every month from 2004-01-01
year = 2004
month = 1
def month_start():
    global year, month
    month_date = datetime.datetime.strptime('{}-{}-01'.format(year, month), '%Y-%m-%d')
    return (month_date - datetime.datetime.strptime('1970-01-01', '%Y-%m-%d')).days

def next_month():
    global year, month
    month += 1
    if month > 12:
        month = 1
        year += 1

# analyze when the last match was played
last_match_threshold = (datetime.datetime.strptime('2023-01-01', '%Y-%m-%d') - datetime.datetime.strptime('1970-01-01', '%Y-%m-%d')).days
player_last_match = {}
for match in matches:
    date = match['date']
    if 'S' in game_type:
        player_a_id = match['player_a_id']
        player_x_id = match['player_x_id']
        player_last_match[player_a_id] = date
        player_last_match[player_x_id] = date
    else:
        player_a_id = match['player_a_id']
        player_b_id = match['player_b_id']
        player_x_id = match['player_x_id']
        player_y_id = match['player_y_id']
        player_last_match[(player_a_id, player_b_id)] = date
        player_last_match[(player_x_id, player_y_id)] = date

save_rankings_number = 128
table_capacity = 32
def save_rankings(filename=None):
    # create history/<year>/<gametype>-<month>.typ
    # save the top 128 players
    # every 32 makes a table
    # format: [ranking, name, nation, rating]
    if not os.path.exists('history/{}'.format(year)):
        os.mkdir('history/{}'.format(year))
    temp = sort_ratings()
    if filename is None:
        filename = 'history/{}/{}-{:02d}.typ'.format(year, game_type, month)
    with open(filename, 'w', encoding='utf-8') as f:
        sex_text = 'Men\'s' if 'M' in game_type else ('Women\'s' if 'W' in game_type else 'Mixed')
        event_text = 'Singles' if 'S' in game_type else 'Doubles'
        for i in range(save_rankings_number):
            if i < len(temp):
                if i % table_capacity == 0:
                    if i != 0:
                        f.write('#pagebreak()\n')
                    f.write(r'''
#set text(font: ("Courier New", "NSimSun"))
#figure(
  caption: "{} {} ({} - {})",
    table(
      columns: 4,
      [Ranking], [Player], [Country/Region], [Rating],
'''.format(sex_text, event_text, i+1, i+32))
                new_line = [i+1, temp[i][1], temp[i][2], int(temp[i][0])]
                last_match = player_last_match[temp[i][3]] if 'S' in game_type else 999999
                if last_match < cur_date and last_match < last_match_threshold:
                    # inactive player
                    new_line[1] = r'#text(gray, "{}")'.format(new_line[1])
                f.write('      [{}], [{}], [{}], [{}],\n'.format(*new_line))
            if i % table_capacity == table_capacity - 1:
                f.write(r'''    )
  )''')
    print('saved rankings to {}'.format(filename))

for match in matches:
    
    # read date and weight
    date = match['date']
    weight = match['weight']
    if cur_date != date:
        # print('date = {}'.format(convert_date(date)))
        cur_date = date
        if cur_date >= month_start():
            print('year = {}, month = {}'.format(year, month))
            save_rankings()
            next_month()
            # print_rankings()
        
    result = match['result']

    # single games
    if 'S' in game_type:
        player_a_id = match['player_a_id']
        player_x_id = match['player_x_id']
        check_player(player_a_id)
        check_player(player_x_id)
        check_result(player_a_id, player_x_id, weight)
        r11, r21 = update_elo(player_a_id, player_x_id, weight, result)
        players_ratings[player_a_id][0] = r11
        players_ratings[player_x_id][0] = r21
        elo_report[player_a_id]['rating'][cur_date] = r11
        elo_report[player_x_id]['rating'][cur_date] = r21
        if abs(weight) >= 0.1:
            players_ratings[player_a_id][3] += 1
            players_ratings[player_x_id][3] += 1
    else:
        # double games
        player_a_id = match['player_a_id']
        player_b_id = match['player_b_id']
        player_x_id = match['player_x_id']
        player_y_id = match['player_y_id']
        if player_b_id < player_a_id:
            player_a_id, player_b_id = player_b_id, player_a_id
        if player_y_id < player_x_id:
            player_x_id, player_y_id = player_y_id, player_x_id
        check_player((player_a_id, player_b_id))
        check_player((player_x_id, player_y_id))
        check_result((player_a_id, player_b_id), (player_x_id, player_y_id), weight, result)
        r11, r21 = update_elo((player_a_id, player_b_id), (player_x_id, player_y_id), weight)
        players_ratings[(player_a_id, player_b_id)][0] = r11
        players_ratings[(player_x_id, player_y_id)][0] = r21
        elo_report[(player_a_id, player_b_id)]['rating'][cur_date] = r11
        elo_report[(player_x_id, player_y_id)]['rating'][cur_date] = r21
        if abs(weight) >= 0.1:
            players_ratings[(player_a_id, player_b_id)][3] += 1
            players_ratings[(player_x_id, player_y_id)][3] += 1

print_rankings()
save_rankings('{}-latest.typ'.format(game_type))
print('correct matches = {}'.format(correct_matches))
print('total matches = {}'.format(total_matches))
print('accuracy = {:.2f}%'.format(correct_matches / total_matches * 100))

if 'S' in game_type:
    # save the elo_report
    elo_report_json = []
    for id, report in elo_report.items():
        if id in players_ratings:
            if players_ratings[id][3] < ranking_least_games:
                continue
        elo_report_json.append({
            'id': id,
            'name': report['name'],
            'nation': report['nation'],
            'rating': [[date, rating] for date, rating in report['rating'].items()]
        })

    # save the elo_report to data/elo_report.json
    with open('data/elo_report_{}.json'.format(game_type), 'w', encoding='utf-8') as f:
        json.dump(elo_report_json, f)