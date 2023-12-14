translation = []
with open('translate.txt', 'r', encoding='utf-8') as f:
    for line in f:
        words = line.split(',')
        translation.append((words[0].strip(), words[1].strip()))

translation.sort()

with open('translate.txt', 'w', encoding='utf-8') as f:
    for t in translation:
        f.write('{}, {}\n'.format(t[0], t[1]))