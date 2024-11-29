import json
import datetime

game_type = 'WS'
# 读取历史ELO数据
with open(f'data/elo_report_{game_type}.json', 'r') as f:
    elo_report = json.load(f)

alltime_report = []

timestart = datetime.datetime.strptime('2004-01-01', '%Y-%m-%d') - datetime.datetime.strptime('1970-01-01', '%Y-%m-%d')
timestart = timestart.days

# 对于每个选手，计算其第10高的ELO值
for player in elo_report:
    name = player['name']
    nation = player['nation']
    rating = [x[1] for x in player['rating']] # if x[0] >= timestart]
    rating.sort(reverse=True)
    if len(rating) >= 10:
        at_rating = rating[9]
        alltime_report.append({
            'name': name,
            'nation': nation,
            'rating': at_rating
        })

# 按照rating排序
alltime_report = sorted(alltime_report, key=lambda x: x['rating'], reverse=True)

# 保留超过2400点的选手
alltime_report = [x for x in alltime_report if x['rating'] >= 2400]

# 输出结果到表格，增加一列排名
table_capacity = 32
def save_rankings(filename=None):
    # create a table for every 32 players
    # format: [ranking, name, nation, rating]
    filename = '{}-history.typ'.format(game_type)
    with open(filename, 'w', encoding='utf-8') as f:
        sex_text = 'Men\'s' if 'M' in game_type else ('Women\'s' if 'W' in game_type else 'Mixed')
        event_text = 'Singles' if 'S' in game_type else 'Doubles'
        for i in range(len(alltime_report)):
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
                for j in range(table_capacity):
                    if i+j < len(alltime_report):
                        player = alltime_report[i+j]
                        f.write(r'''      [{}], [{}], [{}], [{}],
'''.format(i+j+1, player['name'], player['nation'], int(player['rating'])))
            if i % table_capacity == table_capacity - 1 or i == len(alltime_report) - 1:
                f.write(r'''    )
  )''')
    print('saved rankings to {}'.format(filename))

save_rankings()

