#!/bin/bash

#用户使用帮助
usage()
{
    echo "Usage:\t$(basename ${0}) [-S limit_size[M]] [-C] [-i interface] [-f \"tcpdump filter\"] [-d directory] [-l loop count] [-c capture_pkt_num]"
    echo "[-l loop count] 0 means that loop forever"
    echo "[-C] means to compress the result"
}

#退出脚本时的处理
exit_sh()
{
    echo "exec_sh" >> ${logfile}
    if [ -z "$interface" ]; then
        return 1;
    fi

    local pid=
    for pid in $(ps aux | grep -e "tcpdump" | grep -e "${interface}" | awk '{print $2}') 
    do
        echo "kill ${pid}"
        kill ${pid}
    done
    
    return 0
}

# 限制某个目录的大小 删除最旧的数据
function disklimit()
{
    CURMSIZE=`du -m -s ${1} | awk '{print $1}'`
    while [ ${CURMSIZE} -gt ${MAXMSIZE} ]
    do
        echo "CURMSIZE: ${CURMSIZE}; MAXMSIZE: ${MAXMSIZE}" >> $logfile
        # 删除最旧的数据
        rmfile=`ls ${1} -tr | sed "s:^:${1}/:" | head -n 1`
        echo "rmfile: ${rmfile}" >> $logfile
        rm -rf ${rmfile}
        # ls ${1} -tr | sed "s:^:${1}/:" | head -n 1 | rm -rf
        CURMSIZE=`du -m -s ${1} | awk '{print $1}'`
    done
}

#备份以前的目录
bak_old_dir()
{
    local dir="${data_dir}/${interface}"
    if [ ! -d $dir ]; then
        return 0
    fi
    
    #该目录存在，则需要备份以前的目录
    local bak_dir="${dir}_`date \"+%Y%m%d-%H%M%S\"`"
    mv ${dir} ${bak_dir} > /dev/null
    [ "$?" -ne "0" ] && return 1
    
    #创建一个新的目录
    mkdir -p ${dir} > /dev/null
    [ "$?" -ne "0" ] && return 1
    
    return 0
}

function softintr2capture()
{
    # 软中断高于80时 打印need
    need=`cat /proc/cpuinfo | grep processor | awk '{system("mpstat -P "$3" 1 1 | tail -n 1")}' | awk '{if ($8 > 80) {print "need";}}'`
    if [ "$need"x != ""x ]; then
        return 1
    fi
    return 0
}

dump_data()
{
    #创建目录
    local dir="${data_dir}/${interface}"
    if [ ! -d $dir ]; then
        mkdir -p $dir
        [ "$?" -ne "0" ] && return 1
    fi
    #softintr2capture
    #if [ "$?" -ne "1" ]; then
    #    sleep 10
    #    echo "not need capture"
    #    return 0
    #fi

    #循环抓包
    TIME_FMT="+%Y-%m-%d-%H.%M.%S"
    filename=`date "${TIME_FMT}"`
    local data_file="${dir}/autocapture_${filename}.pcap"        
    echo "-----------`date` begin tcpdump----------" >> $logfile
    echo "$data_file" >> $logfile        
    tcpdump -i $interface $dump_filter -n -c ${count} -w $data_file 2>>$logfile
    [ "$?" -ne "0" ] && { echo "invalid interface or tcpdump filter" >& 2; return 1; }
    # 压缩结果
    if [ ${need_compress} != 0 ]; then
        tar -czvf "${data_file}.tar.gz" ${data_file}
        rm -rf ${data_file}
    fi        
    echo "-----------`date` end tcpdump----------" >> $logfile        
    # 限制目录磁盘大小
    disklimit ${dir}
    return 0
}

#解析参数
parse_arg()
{
    #验证参数
    if [ "$#" -lt "4" ] || [ "$#" -gt "13" ]; then
        usage
        return 1
    fi

    while getopts :i:c:d:f:l:CS: opt
    do
        case $opt in
        i)    interface=$OPTARG
            ;;
        c)    count=$OPTARG
            ;;
        d)    data_dir=$OPTARG
            ;;
        f)    dump_filter=$OPTARG
            ;;
        l)    loop=$OPTARG
            ;;
        C)    need_compress=1
            ;;
        S)    MAXMSIZE=$OPTARG
            ;;
        ?)    echo "$(basename ${0}): invalid option -$OPTARG" >& 2
            usage
            return 1
        esac
    done

    #保证参数有效
    [ -z "${interface}" ] && { echo "invalid interface" ; usage; return 1; }
    [ -z "${dump_filter}" ] && { echo "invalid \"tcpdump filter\""; usage; return 1; }    
    [ -z "${count}" ] && { count=500000; echo "count used default value: $count"; }
    [ -z "${data_dir}" ] && { data_dir="/aclog/dump_data"; echo "data_dir used default value: $data_dir"; }
    [ -z "${loop}" ] && { loop=0; echo "loop used default value: $loop"; }    
    [ -z "${MAXMSIZE}" ] && { MAXMSIZE=1000; echo "MAXMSIZE used default value: $MAXMSIZE M"; }    
    
    return 0
}

# 限制大小
MAXMSIZE=
# 是否需要压缩
need_compress=0

#接口
interface=

#抓包数
count=

#数据包存储目录
data_dir=/data/aclog

#抓包过滤条件
dump_filter=

#循环抓包次数
loop=

#解析参数
parse_arg "$@"
[ "$?" -ne "0" ] && { exit 1; }

logfile="${data_dir}/dump_data.log"

#处理信号
trap 'exit_sh; exit 0' SIGINT SIGQUIT SIGTERM

#备份目录
bak_old_dir
[ "$?" -ne "0" ] && { exit 1; }

#开始抓包
i=$loop
while [ "$loop" -eq "0" ] || [ "$i" -gt "0" ]; do
    
    dump_data
    
    if [ "$?" -ne "0" ]; then
        echo "invalid argument"
        exit 1
    fi
    
    [ "$loop" -ne "0" ] && ((i--))
    
done
