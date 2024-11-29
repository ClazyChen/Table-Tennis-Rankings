import json
import os

# analyze the json data
# vw_tournaments___id_raw -> uid
# vw_tournaments___tournament_id_raw -> id
# vw_tournaments___yr_raw -> year
# vw_tournaments___tournament_raw -> name
# vw_tournaments___type -> type
# vw_tournaments___kind -> kind
# vw_tournaments___organizer -> organizer
# vw_tournaments___tour_start_raw -> start
# vw_tournaments___tour_end_raw -> end
# other fields will be dropped

# event type -> coefficient
# 1. Olympic Games: 3.0 奥运会
# 2. WTTC: 2.5 世乒赛
# 3. World Cup: 2.0 世界杯
#    WTT Grand Smash: 1.6 大满贯赛
# 4. WTT Finals: 1.4 世界杯总决赛
#    World Tour / Pro Tour; Grand Finals | Finals 总决赛
# 5. WTT Champions: 1.2 冠军赛
#    T2 Diamond: 1.2 钻石赛
#    WTT Contender Series (Star): 1.1 球星挑战赛
#    World Tour / Pro Tour; Platinum 白金赛
#    World Tour / Pro Tour; Super Series 超级赛
#    World Tour / Pro Tour; Major Series 大师赛
# 6. Continental Games: 1.0 大洲运动会
#    Continental 大洲杯/大洲锦标赛
#    Olympic (Youth) 青奥会
#    WJTTC 世青赛
#    WTT Contender Series 挑战赛
#    World Tour / Pro Tour 公开赛
#    World Tour / Pro Tour; Challenge Series 挑战赛
#    Challenge 挑战赛
#    Olympic Qualification 奥运资格赛
#    World Youth Championships 青少年锦标赛
#    World Cadet Challenge 青少年挑战赛
#    World Junior Circuit; Finals 青年巡回赛（总决赛）
# 7. WTT Feeder Series: 0.8  支线赛
#    Multi sport events 区域运动会
#    Other events 区域锦标赛
#    WTT Youth Contender Series (Star) 青年球星挑战赛
#    World Junior Circuit; Platinum | Golden 青年巡回赛（金牌）
#    Olympic (Youth; Qualification/Road) 青奥会资格赛
#    Continental (Youth) 大洲青年赛
#    Other events (Youth) 区域青年赛
#    World Junior Circuit; Premium 青年巡回赛（高级）
#    WTT Youth Contender Series 青年挑战赛
#    World Junior Circuit 青年巡回赛

# set the coefficient type
def is_youth(name):
    p1 = 'Youth' in name or 'Cadet' in name or 'Junior' in name
    p2 = 'youth' in name or 'cadet' in name or 'junior' in name
    p3 = 'U21' in name or 'U-21' in name or 'YOG' in name
    p4 = 'U15' in name or 'U-15' in name or 'U18' in name or 'U-18' in name
    return p1 or p2 or p3 or p4

def coefficient(type_, name):
    if 'China vs World Team' in name or 'China vs. World Team' in name:
        return 1.2
    if 'Tournament of Champions' in name:
        return 1.5
    if type_ == "Olympic Games":
        if 'Qualification' in name or 'Road' in name:
            return 0.2
        elif is_youth(name):
            return 1.0
        else:
            return 3.0
    elif type_ == "WTTC":
        return 2.5
    elif type_ == "World Cup":
        return 2.0
    elif type_ == "WTT Finals":
        return 1.5
    elif type_ == 'World Tour / Pro Tour':
        if 'Finals' in name:
            return 1.5
        elif 'Platinum' in name:
            return 1.3
        else:
            return 1.2
    elif type_ == "WTT Champions":
        return 1.3
    elif type_ == "WTT Grand Smash":
        return 1.4
    elif type_ == "Continental Games":
        if is_youth(name):
            return 0.25
        else:
            if 'Asian' in name or 'European' in name:
                return 1.6
            else:
                return 0.8
    elif type_ == "Continental":
        if is_youth(name):
            if 'Asian' in name or 'European' in name:
                return 0.5
            else:
                return 0.25
        else:
            if 'Asian' in name or 'European' in name:
                return 1.5
            else:
                return 0.75
    elif type_ == 'WTT Contender Series':
        if 'Star' in name:
            return 1.1
        else:
            return 1.0
    elif type_ == 'T2 Diamond':
        return 1.0
    elif type_ == 'WJTTC':
        return 0.8
    elif type_ == 'Challenge':
        if 'Plus' in name:
            return 1.1
        else:
            return 1.0
    elif type_ == 'Olympic Qualification':
        return 0.6
    elif type_ == 'World Youth Championships':
        return 0.8
    elif type_ == 'World Cadet Challenge':
        return 0.65
    elif type_ == 'World Junior Circuit':
        if 'Finals' in name:
            return 0.5
        elif 'Platinum' in name or 'Golden' in name:
            return 0.4
        else:
            return 0.3
    elif type_ == 'WTT Feeder Series':
        return 1.0
    elif type_ == 'Multi sport events':
        # 亚运会
        if 'Asian' in name and 'Guangzhou' in name:
            return 1.6
        if 'Asian' in name and 'Incheon' in name:
            return 1.6
        if 'Pan American' in name and 'Guadalajara' in name:
            return 0.8
        if is_youth(name):
            return 0.2
        else:
            return 0.6
    elif type_ == 'Other events':
        # Open 按照挑战赛处理
        if 'Open,' in name:
            if is_youth(name):
                return 0.3
            else:
                return 1.0
        # 世乒赛预选赛
        if 'WTTC' in name:
            return 0.5
        # 欧青赛
        if 'Top 10' in name:
            return 0.5
        # 剩余的地区比赛
        if is_youth(name):
            return 0.2
        else:
            return 0.6
    elif type_ == 'WTT Youth Contender Series':
        if 'Star' in name:
            return 0.4
        else:
            return 0.3
    else:
        return 0.1

event_file_number = 16
while os.path.exists('events/events_{}.json'.format(event_file_number)):
    event_file_number += 1

profile = []
for i in range(0, event_file_number):
    json_file = 'events/events_{}.json'.format(i)
    with open(json_file, 'r') as f:
        data = json.load(f)
        # data = [[{ t1 }, { t2 }, { t3 } , ...]]
        for tournament in data[0]:
            uid = tournament['vw_tournaments___id_raw']
            id = tournament['vw_tournaments___tournament_id_raw']
            year = tournament['vw_tournaments___yr_raw']
            name = tournament['vw_tournaments___tournament_raw']
            type_ = tournament['vw_tournaments___type']
            organizer = tournament['vw_tournaments___organizer']
            start = tournament['vw_tournaments___tour_start_raw']
            end = tournament['vw_tournaments___tour_end_raw']
            profile.append({
                'uid': uid,
                'id': id,
                'year': year,
                'name': name,
                'type': type_,
                'organizer': organizer,
                'start': start,
                'end': end,
                'coefficient': coefficient(type_, name)
            })
    print('analyzed {}'.format(json_file))

# sort the profile by id (decreasing)
profile = sorted(profile, key=lambda x: x['id'], reverse=True)

# save the profile to a json file
with open('events/events_profile.json', 'w') as f:
    json.dump(profile, f)