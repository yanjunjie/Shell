# Shell
shell 实例手册


dump_data.sh
nohup /aclog/dump_data.sh -i eth9  -f "( host 11.201.x.x )" -l 0 -c 10000 -d /aclog/data -C &
nohup /aclog/dump_data.sh -i eth9  -f "( host 11.201.x.x  or host  11.201.x.x )" -l 0 -c 10000 -d /aclog/data -C &
