import os

files_path = [x for x in os.listdir('.') if x[-3:] == 'jpg']

for i in range(len(files_path)):
    os.rename(files_path[i], f'bg_{i:>02d}.jpg')
