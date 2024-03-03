import os

translation = {
    'Ranking': '排名',
    'Player': '运动员',
    'Country/Region': '国家/地区',
    'Rating': '积分'
}
with open('translate.txt', 'r', encoding='utf-8') as f:
    for line in f:
        words = line.split(',')
        translation[words[0].strip()] = words[1].strip()

# for every file in history/{}, 2004-2023
# replace the words in the file
def translate(src, dst):
    with open(src, 'r', encoding='utf-8') as f:
        text = f.read()
        for t in translation:
            text = text.replace(t + "]", translation[t] + "]")
            text = text.replace(t + "\"", translation[t] + "\"")
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(text)

for year in range(2004, 2025):
    dir_name = 'history/{}'.format(year)
    cn_dir_name = 'history_CN/{}'.format(year)
    if not os.path.exists(cn_dir_name):
        os.mkdir(cn_dir_name)
    for file_name in os.listdir(dir_name):
        file_path = '{}/{}'.format(dir_name, file_name)
        cn_file_path = '{}/{}'.format(cn_dir_name, file_name)
        translate(file_path, cn_file_path)
        print('translated {}'.format(file_path))

for event in ['MS', 'WS']:
    translate('{}-latest.typ'.format(event), '{}-latest_CN.typ'.format(event))