#!/bin/bash
# https://github.com/Aniverse/inexistence
# script_update=2020.09.15
# script_version=r12031
# This var will recover other script's var when source
################################################################################################ Usage Guide

usage_guide() {
s=/root/check-sys.sh;rm -f $s ; nano $s
wget -q https://raw.githubusercontent.com/BlueSkyXN/ChangeSource/master/check-sys.sh -O /root/check-sys.sh

if [[ -f /root/check-sys.sh ]]; then
    source /root/check-sys.sh
else
    source <(wget -qO- https://raw.githubusercontent.com/BlueSkyXN/ChangeSource/master/check-sys.sh)
fi
}

################################################################################################ OS Check

get_opsy() {
    # Fedora, CentOS
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}'          /etc/redhat-release && return
    # Gentoo, Slackware, Arch Linux, Alpine Linux, Ubuntu, Debian, OpenSUSE
    [ -f /etc/os-release     ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release     && return
    # Ubuntu
    [ -f /etc/lsb-release    ] && awk -F'[="]+' '/DESCRIPTION/{print $2}'       /etc/lsb-release    && return
}

has_cmd() {
    local cmd="$1"
    if  eval type type > /dev/null 2>&1; then
        eval type "$cmd" > /dev/null 2>&1
    elif command > /dev/null 2>&1; then
         command -v "$cmd" > /dev/null 2>&1
    else
        which "$cmd" > /dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

running_kernel=$(uname -r 2>&1)
arch=$(uname -m 2>&1)
if  has_cmd "getconf" ; then
    lbit=$( getconf LONG_BIT )
else
    echo ${arch} | grep -q "64" && lbit="64" || lbit="32"
fi
[[ -z $arch ]] && arch=$(echo "x${lbit}")

DISTRO=$(awk -F'[= "]' '/PRETTY_NAME/{print $3}' /etc/os-release)
DISTROL=$(echo $DISTRO | tr 'A-Z' 'a-z')
[[ $DISTRO =~ (Ubuntu|Debian) ]] && CODENAME=$(cat /etc/os-release | grep VERSION= | tr '[A-Z]' '[a-z]' | sed 's/\"\|(\|)\|[0-9.,]\|version\|lts//g' | awk '{print $2}' | head -1)
[[ $DISTRO == Ubuntu ]] && osversion=$(grep Ubuntu /etc/issue | head -1 | grep -oE  "[0-9.]+")
[[ $DISTRO == Debian ]] && osversion=$(cat /etc/debian_version)
[[ ! $DISTRO =~ (Ubuntu|Debian) ]] && DISTRO=$(get_opsy)

check_pm() {
    if   type dnf     >/dev/null 2>&1; then  # Fedora, CentOS 8
        pm=dnf
    elif type yum     >/dev/null 2>&1; then  # CentOS
        pm=yum
    elif type apt-get >/dev/null 2>&1; then  # Debian/Ubuntu
        pm=apt-get
    elif type pacman  >/dev/null 2>&1; then  # ArchLinux
        pm=pacman
    elif type zypper  >/dev/null 2>&1; then  # SUSE
        pm=zypper
    elif type emerge  >/dev/null 2>&1; then  # Gentoo
        pm=emerge
    elif type apk     >/dev/null 2>&1; then  # Alpine
        pm=apk
    fi
}

check_pm

if [[ $DISTRO =~ (Debian|Ubuntu) ]]; then
    displayOS="$DISTRO $osversion $CODENAME ($arch)"
else
    displayOS="$DISTRO ($arch)"
fi



################################################################################################
################################################################################################ System spec check
################################################################################################



cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )

# Check interface
wangka1=$(cat /proc/net/dev | sort -rn -k2 | head -1 | awk -F':' '{print $1}')
wangka2=$(ip addr 2>&1 | grep -B2 $(ip route get 1 2>&1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p') | grep -i broadcast | cut -d: -f 2 | cut -d@ -f 1 | sed 's/ //g')
interface=$wangka1
[[ -n $wangka2 ]] && interface=$wangka2


calc_disk() {
    local total_size=0 ; local array=$@
    #shellcheck disable=SC2068
    for size in ${array[@]} ; do
        [ "${size}" == "0" ] && size_t=0 || size_t=`echo ${size:0:${#size}-1}`
        [ "`echo ${size:(-1)}`" == "K" ] && size=0
        [ "`echo ${size:(-1)}`" == "M" ] && size=$( awk 'BEGIN{printf "%.1f", '$size_t' / 1024}' )
        [ "`echo ${size:(-1)}`" == "T" ] && size=$( awk 'BEGIN{printf "%.1f", '$size_t' * 1024}' )
        [ "`echo ${size:(-1)}`" == "G" ] && size=${size_t}
        total_size=$( awk 'BEGIN{printf "%.1f", '$total_size' + '$size'}' )
    done
    echo ${total_size}
}


hardware_check_1() {
    # CPU
    cputhreads=$( grep 'processor' /proc/cpuinfo | sort -u | wc -l )
    cpucores_single=$( grep 'core id' /proc/cpuinfo | sort -u | wc -l )
    cpunumbers=$( grep 'physical id' /proc/cpuinfo | sort -u | wc -l )  # physical_cpu_number=$( grep 'physical id' /proc/cpuinfo | cut -c15-17 )
    cpucores=$( expr $cpucores_single \* $cpunumbers ) # cpu_percent=$( top -b -n 1 | grep Cpu | awk '{print $2}' | cut -f 1 -d "." )
    freq=$( awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    if [[ $virtual == "No Virtualization Detected" ]] || [[ $virtual == Docker ]]; then
        [[ $cpunumbers == 2 ]] && CPUNum='Dual ' ; [[ $cpunumbers == 4 ]] && CPUNum='Quad ' ; [[ $cpunumbers == 8 ]] && CPUNum='Octa '
    fi

    disk_size1=($( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|devtmpfs|by-uuid|chroot|Filesystem' | awk '{print $2}' ))
    disk_size2=($( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|devtmpfs|by-uuid|chroot|Filesystem' | awk '{print $3}' ))
    disk_total_size=$( calc_disk "${disk_size1[@]}" )
    disk_used_size=$( calc_disk "${disk_size2[@]}" )
    TOTAL_DISK=$(df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs -t swap --total -h | grep total | awk '{ print $2 }')

    # If SSD
    cat /sys/block/sd*/queue/rotational 2>/dev/null | grep -q 0 && SSD=yes
    cat /sys/block/vd*/queue/rotational 2>/dev/null | grep -q 0 && SSD=yes

    # memory
    tram=$(  free -m | awk '/Mem/  {print $2}' )
    uram=$(  free -m | awk '/Mem/  {print $3}' )
    swap=$(  free -m | awk '/Swap/ {print $2}' )
    uswap=$( free -m | awk '/Swap/ {print $3}' )
    memory_usage=`free -m |grep -i mem | awk '{printf ("%.2f\n",$3/$2*100)}'`%

    # Sys info
    users=`users | wc -w`
    date=$( date +%Y-%m-%d" "%H:%M:%S )
    processes=`ps aux | wc -l`
    uptime1=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days %d hour %d min\n",a,b,c)}' /proc/uptime )
    uptime2=`uptime | grep -ohe 'up .*' | sed 's/,/\ hours/g' | awk '{ printf $2" "$3 }'`
    if has_cmd "w"; then
        load=$( w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
    elif has_cmd "uptime"; then
        load=$( uptime | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
    fi
}




check_tcp_acc() {
    tcp_control=$( cat /proc/sys/net/ipv4/tcp_congestion_control 2>&1 )
    tcp_control_all=$( cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>&1 )
    tcp_c_name=$tcp_control
    [[ $tcp_control == bbr_powered ]] && tcp_c_name="bbr_powered (用 Vicer 脚本安装的 Yankee 版魔改 BBR)"
    [[ $tcp_control == tsunami     ]] && tcp_c_name="tsunami (Yankee 版魔改 BBR)"
    [[ $tcp_control == nanqinlang  ]] && tcp_c_name="nanqinlang (南琴浪版魔改 BBR)"
    ps aux | grep -v grep | grep appex -q && tcp_c_name="锐速"
}


################################################################################################
################################################################################################ Long
################################################################################################


detectOs() {
    local DISTRIB_ID=
    local DISTRIB_DESCRIPTION=
    if [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
    fi

    # Add Alpine Linux detection
    if   cat /etc/os-release | grep -i Alpine ; then
        os=alpine
        os_long="$(awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release)"
    elif [ -f /etc/fedora-release ]; then
        os=fedora
        os_long="$(cat /etc/fedora-release)"
    # Must be before PCLinuxOS, Mandriva, and a whole bunch of other OS tests
    elif [ -f /etc/unity-release ]; then
        os=unity
        os_long="$(cat /etc/unity-release)"
    elif [ -f /etc/pclinuxos-release ]; then
        os=pclinuxos
        os_long="$(cat /etc/pclinuxos-release)"
    elif [ "$DISTRIB_ID" = "Ubuntu" ]; then
        os=debian
        os_long="$DISTRIB_DESCRIPTION"
    elif [ "$DISTRIB_ID" = "LinuxMint" ]; then
        os=debian
        os_long="$DISTRIB_DESCRIPTION"
    # Must be before Debian
    elif [ "$DISTRIB_ID" = "Peppermint" ]; then
        os=debian
        os_long="$DISTRIB_DESCRIPTION"
    elif [ "$DISTRIB_ID" = "MEPIS" ]; then
        os=debian
        os_long="$DISTRIB_DESCRIPTION"
    elif [ -f /etc/clearos-release ]; then
        os=fedora
        os_long="$(cat /etc/clearos-release)"
    elif [ -f /etc/pardus-release ]; then
        os=pardus
        os_long="$(cat /etc/pardus-release)"
    elif [ -f /etc/chakra-release ]; then
        os=arch
        os_long="Chakra $(cat /etc/chakra-release)"
    elif [ -f /etc/frugalware-release ]; then
        os=frugalware
        os_long="$(cat /etc/frugalware-release)"
    # Must test this before Gentoo
    elif [ -f /etc/sabayon-release ]; then
        os=sabayon
        os_long="$(cat /etc/sabayon-release)"
    elif [ -f /etc/arch-release ]; then
        os=arch
        os_long="Arch Linux"
    elif [ -f /etc/gentoo-release ]; then
        os=gentoo
        os_long="$(cat /etc/gentoo-release)"
    elif [ -f /etc/SuSE-release ]; then
        os=opensuse
        os_long="$(grep SUSE /etc/SuSE-release | head -n1)"
    elif [ -f /etc/debian_version ]; then
        os=debian
        local prefix=
        if ! uname -s | grep -q GNU; then
            prefix="GNU/"
        fi
        os_long="Debian $prefix$(uname -s) $(cat /etc/debian_version)"
    # Must test for mandriva before centos since it also has /etc/redhad-release
    elif [ -f /etc/mandriva-release ]; then
        os=mandriva
        os_long="$(cat /etc/mandriva-release)"
    elif [ -f /etc/redhat-release ]; then
        os=fedora
        os_long="$(cat /etc/redhat-release)"
    elif [ -f /etc/vector-version ]; then
        os=slaptget
        os_long="VectorLinux $(cat /etc/vector-version)"
    elif [ -f /etc/slackware-version ]; then
        os=slackware
        os_long="$(cat /etc/slackware-version)"
        #if isProgramInstalled slapt-get; then
        #    os=slaptget
        #else
        #    os=other
        #fi
    elif [ "$(uname -s)" = "FreeBSD" ]; then
        os=freebsd
        os_long=FreeBSD
    elif [ "$(uname -s)" = "DragonFly" ]; then
        os=dragonfly
        os_long="DragonFly BSD"
    elif [ "$(uname -s)" = "OpenBSD" ]; then
        os=openbsd
        os_long=OpenBSD
    elif [ "$(uname -s)" = "NetBSD" ]; then
        os=netbsd
        os_long=NetBSD
    else
        os=other
        os_long="$(uname -s)"
    fi

    os_long="${os_long:-$(uname -s)}"
}


detectOs


# Modified, Origin see here: https://github.com/Tarcaxoxide/i
# pm_action update-source ; pm_action install wget
function pm_action(){
    # args=$(echo "$*" |grep -v "$1")
    args="${*:2}"
######################################################
    if [ "$1" == "install" ];then
        if type "emerge" &> /dev/null; then 
            emerge "$args"
        elif type "pacman" &> /dev/null; then
            pacman -S --noconfirm "$args"
        elif type "apt-get" &> /dev/null; then
            apt-get install -y "$args"
        elif type "zypper" &> /dev/null; then
            zypper install -y "$args"
        elif type "dnf" &> /dev/null; then
            dnf install -y "$args"
        elif type "yum" &> /dev/null; then
            yum install -y "$args"
        elif type "apk" &> /dev/null; then
            apk add "$args"
        fi
    fi
######################################################
    if [ "$1" == "uninstall" ];then
        if type "emerge" &> /dev/null; then
            emerge --unmerge "$args"
        elif type "pacman" &> /dev/null; then
            pacman -Rsc "$args"
        elif type "apt-get" &> /dev/null; then
            apt-get remove "$args"
        elif type "zypper" &> /dev/null; then
            zypper remove "$args"
        elif type "dnf" &> /dev/null; then
            dnf remove "$args"
        elif type "yum" &> /dev/null; then
            yum remove "$args"
        elif type "apk" &> /dev/null; then
            apk del "$args"
        fi
    fi
######################################################
    if [ "$1" == "upgrade" ];then
        if type "emerge" &> /dev/null; then
            emerge --update --deep "$args"
        elif type "pacman" &> /dev/null; then
            pacman -Syu "$args"
        elif type "apt-get" &> /dev/null; then
            apt-get install --only-upgrade "$args"
        elif type "zypper" &> /dev/null; then
            zypper update "$args"
        elif type "dnf" &> /dev/null; then
            dnf update "$args"
        elif type "yum" &> /dev/null; then
            yum update "$args"
        elif type "apk" &> /dev/null; then
            apk add --upgrade "$args"
        fi
    fi

    if [ "$1" == "update" ];then
        if type "emerge" &> /dev/null; then
            emerge --sync
        elif type "pacman" &> /dev/null; then
            pacman -Syy
        elif type "apt-get" &> /dev/null; then
            apt-get update
        elif type "zypper" &> /dev/null; then
            zypper refresh
        elif type "dnf" &> /dev/null; then
            dnf check-update
            # dnf makecache
        elif type "yum" &> /dev/null; then
            yum check-update
            # yum makecache
        elif type "apk" &> /dev/null; then
            apk update
        fi
    fi

    if [ "$1" == "all-update" ];then
        if type "emerge" &> /dev/null; then
            emerge --update --deep @world
        elif type "pacman" &> /dev/null; then
            pacman -Syyu
        elif type "apt-get" &> /dev/null; then
            apt-get dist-upgrade
        elif type "zypper" &> /dev/null; then
            zypper update
        elif type "dnf" &> /dev/null; then
            dnf update
            dnf upgrade
        elif type "yum" &> /dev/null; then
            yum update
        elif type "apk" &> /dev/null; then
            apk upgrade
        fi
    fi

######################################################
    if [ "$1" == "list" ];then
        if type "emerge" &> /dev/null; then
            echo command undefined
        elif type "pacman" &> /dev/null; then
            pacman -Q | more
        elif type "apt-get" &> /dev/null; then
            echo command undefined
        elif type "zypper" &> /dev/null; then
            zypper packages
        elif type "dnf" &> /dev/null; then
            dnf list installed
        elif type "yum" &> /dev/null; then
            yum list
        elif type "apk" &> /dev/null; then
            apk list
        fi
    fi
######################################################
    if [ "$1" == "search" ];then
        if type "emerge" &> /dev/null; then
            emerge --search "$args"
        elif type "pacman" &> /dev/null; then
            pacman -Ss "$args"
        elif type "apt-get" &> /dev/null; then
            apt-cache search "$args"
        elif type "zypper" &> /dev/null; then
            zypper search "$args"
        elif type "dnf" &> /dev/null; then
            dnf search "$args"
        elif type "yum" &> /dev/null; then
            yum search "$args"
        elif type "apk" &> /dev/null; then
            apk search "$args"
        fi
    fi
######################################################
    if [ "$1" == "info" ];then
        if type "emerge" &> /dev/null; then
            emerge --info "$args"
        elif type "pacman" &> /dev/null; then
            pacman -Si "$args"
        elif type "apt-get" &> /dev/null; then
            apt-cache show "$args"
        elif type "zypper" &> /dev/null; then
            zypper info "$args"
        elif type "dnf" &> /dev/null; then
            dnf info "$args"
        elif type "yum" &> /dev/null; then
            yum info "$args"
        elif type "apk" &> /dev/null; then
            apk info -a "$args"
        fi
    fi
######################################################
    if [ "$1" == "cleanup" ];then
        if type "emerge" &> /dev/null; then
            emerge --ask --clean --deep
            emerge --ask --depclean
        elif type "pacman" &> /dev/null; then
            pacman -Sc
        elif type "apt-get" &> /dev/null; then
            apt-get autoclean
        elif type "zypper" &> /dev/null; then
            zypper clean --all
        elif type "dnf" &> /dev/null; then
            dnf clean all
        elif type "yum" &> /dev/null; then
            yum clean all
        elif type "apk" &> /dev/null; then
            apk cache clean
        fi
    fi
###################################################### To be fixed
    if [ "$1" == "show-source" ];then
        if type "emerge" &> /dev/null; then
            sleep 0
        elif type "pacman" &> /dev/null; then
            cat /etc/pacman.d/mirrorlist
        elif type "apt-get" &> /dev/null; then
            cat /etc/apt/sources.list
        elif type "zypper" &> /dev/null; then
            cat /etc/zypp/repos.d/OSS.repo
        elif type "dnf" &> /dev/null; then
            cat /etc/yum.repos.d/fedora.repo
            cat /etc/yum.repos.d/fedora-updates.repo
        elif type "yum" &> /dev/null; then
            cat /etc/yum.repos.d/CentOS-Base.repo
        elif type "apk" &> /dev/null; then
            cat /etc/apk/repositories
        fi
    fi
}

# Virt-what
check_virt() {
    local virtualx=$(dmesg 2>&1)
    local uname_p=$(uname -p 2>&1)
    local dmi=$(LANG=C dmidecode 2>&1)

    if  [ $(which dmidecode) ]; then
        sys_manu=$(dmidecode -s system-manufacturer) 2>/dev/null
        sys_product=$(dmidecode -s system-product-name) 2>/dev/null
        sys_ver=$(dmidecode -s system-version) 2>/dev/null
    else
        sys_manu=""
        sys_product=""
        sys_ver=""
    fi
    
    if grep docker /proc/1/cgroup -qa 2>/dev/null ; then
        virtual="Docker"
    elif grep lxc /proc/1/cgroup -qa 2>/dev/null; then
        virtual="Lxc"
    elif grep -qa container=lxc /proc/1/environ 2>/dev/null; then
        virtual="Lxc"
    elif [[ -f /proc/user_beancounters ]]; then
        virtual="OpenVZ"
    elif [[ "$virtualx" == *kvm-clock* ]] || [[ "$cname" == *KVM* ]]; then
        virtual="KVM"
    elif [[ "$virtualx" == *"VMware Virtual Platform"* ]]; then
        virtual="VMware"
    elif [[ "$virtualx" == *"Parallels Software International"* ]]; then
        virtual="Parallels"
    elif [[ "$virtualx" == *VirtualBox* ]]; then
        virtual="VirtualBox"
    elif grep -q 'UML' "/proc/cpuinfo"; then
        virtual="UML (User Mode Linux)"
    elif grep -q '^vendor_id.*PowerVM Lx86' "${root}/proc/cpuinfo"; then
        virtual="PowerVM Lx86"
    elif cat "/proc/self/status" | grep -q "VxID: [0-9]*" ; then
        if grep -q "VxID: 0$" "/proc/self/status"; then
            virtual="Linux VServer Host"
        else
            virtual="Linux VServer Guest"
        fi
    elif grep -q '^vendor_id.*IBM/S390' "/proc/cpuinfo" ; then
        if grep -q 'VM.*Control Program.*z/VM' "/proc/sysinfo"; then
            virtual="IBM SystemZ ZVM"
        elif grep -q '^LPAR' "${root}/proc/sysinfo"; then
            virtual="IBM SystemZ LPAR"
        else
            virtual="IBM SystemZ"
        fi
    elif echo "$dmi" | grep -q 'Manufacturer.*HITACHI' && echo "$dmi" | grep -q 'Product.* LPAR'; then
        virtual="Virtage"
    elif [[ -d /proc/xen ]]; then
        if grep -q "control_d" "/proc/xen/capabilities" 2>/dev/null; then
            virtual="Xen-Dom0"
        else
            virtual="Xen-DomU"
        fi
    elif [ -f "/sys/hypervisor/type" ] && grep -q "xen" "/sys/hypervisor/type"; then
        virtual="Xen"
    elif [[ "$sys_manu" == *"Microsoft Corporation"* ]]; then
        if [[ "$sys_product" == *"Virtual Machine"* ]]; then
            if [[ "$sys_ver" == *"7.0"* || "$sys_ver" == *"Hyper-V" ]]; then
                virtual="Hyper-V"
            else
                virtual="Microsoft Virtual Machine"
            fi
        fi
    else
        virtual="No Virtualization Detected"
    fi

    if [ "$uname_p" = "ia64" ]; then
        if [ -d "/sys/bus/xen" -a ! -d "/sys/bus/xen-backend" ]; then
           virtual="Xen-HVM"
        fi
    fi

    [[ "$virtual" != KVM ]] && grep -q QEMU /proc/cpuinfo && virt="QEMU"
}

check_virt


################################################################################################
################################################################################################ IP-Related
################################################################################################



function isValidIpAddress() { echo $1 | grep -qE '^[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?$' ; }
function isInternalIpAddress() { echo $1 | grep -qP '(192\.168\.((\d{1,2})|(1\d{2})|(2[0-4]\d)|(25[0-5]))\.((\d{1,2})$|(1\d{2})$|(2[0-4]\d)$|(25[0-5])$))|(172\.((1[6-9])|(2\d)|(3[0-1]))\.((\d{1,2})|(1\d{2})|(2[0-4]\d)|(25[0-5]))\.((\d{1,2})$|(1\d{2})$|(2[0-4]\d)$|(25[0-5])$))|(10\.((\d{1,2})|(1\d{2})|(2[0-4]\d)|(25[0-5]))\.((\d{1,2})|(1\d{2})|(2[0-4]\d)|(25[0-5]))\.((\d{1,2})$|(1\d{2})$|(2[0-4]\d)$|(25[0-5])$))' ; }

# From nench.sh
function redact_ip() {
    case "$1" in
        *.*)
            printf '%s.xxx.xxx\n' "$(printf '%s\n' "$1" | cut -d . -f 1-2)"
            ;;
        *:*)
            printf '%s:xxxx:xxxx\n' "$(printf '%s\n' "$1" | cut -d : -f 1-2)"
            ;;
    esac
}

ipv4_check() {
    echo -e "${bold}Checking your server's public IPv4 address ...${normal}"
    # serveripv4=$( ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' )
    # serveripv4=$( ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:" )
    # serveripv4=$( ip route get 8.8.8.8 | awk '{print $3}' )
    # isInternalIpAddress "$serveripv4" || serveripv4=$( wget --no-check-certificate -t1 -T6 -qO- v4.ipv6-test.com/api/myip.php )
    serveripv4=$( ip route get 1 2>&1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p' )
    isInternalIpAddress "$serveripv4" && serveripv4=$( wget --no-check-certificate -4 -t1 -T6 -qO- v4.ipv6-test.com/api/myip.php )
    isValidIpAddress    "$serveripv4" || serveripv4=$( wget --no-check-certificate -4 -t1 -T6 -qO- ip.sb)
    isValidIpAddress    "$serveripv4" || serveripv4=$( wget --no-check-certificate -4 -t1 -T6 -qO- checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//' )
    isValidIpAddress    "$serveripv4" || serveripv4=$( wget --no-check-certificate -4 -t1 -T7 -qO- ipecho.net/plain )
    isValidIpAddress "$serveripv4" || { echo "${bold}${red}${shanshuo}ERROR ${jiacu}${underline}Failed to detect your public IPv4 address, use internal address instead${normal}" ; serveripv4=$( ip route get 8.8.8.8 2>&1 | awk '{print $3}' ) ; }
    serveripv4_show=$(redact_ip "$serveripv4") ; [[ $full_ip == 1 ]] && serveripv4_show=$serveripv4
}

ipv6_check() {
    echo -e "${bold}Checking your server's public IPv6 address ...${normal}"
    serveripv6=$( wget -t1 -T5 -qO- v6.ipv6-test.com/api/myip.php | grep -Eo "[0-9a-z:]+" | head -n1 )
    # serveripv6=$( wget --no-check-certificate -qO- -t1 -T8 ipv6.icanhazip.com )
    # serverlocalipv6=$( ip addr show dev $interface | sed -e's/^.*inet6 \([^ ]*\)\/.*$/\1/;t;d' | grep -v fe80 | head -n1 )
    serveripv6_show=$(redact_ip "$serveripv6") ; [[ $full_ip == 1 ]] && serveripv6_show=$serveripv6
}

ip_ipapi() {
    mkdir -p $HOME/.abench
    wget --no-check-certificate -t1 -T6 -qO- https://ipapi.co/json > $HOME/.abench/ipapi 2>&1
    ccoodde=$( cat $HOME/.abench/ipapi | grep \"country\"      | awk -F '"' '{print $4}' ) 2>/dev/null
    country=$( cat $HOME/.abench/ipapi | grep \"country_name\" | awk -F '"' '{print $4}' ) 2>/dev/null
    regionn=$( cat $HOME/.abench/ipapi | grep \"region\"       | awk -F '"' '{print $4}' ) 2>/dev/null
    cityyyy=$( cat $HOME/.abench/ipapi | grep \"city\"         | awk -F '"' '{print $4}' ) 2>/dev/null
    isppppp=$( cat $HOME/.abench/ipapi | grep \"org\"          | awk -F '"' '{print $4}' ) 2>/dev/null
    asnnnnn=$( cat $HOME/.abench/ipapi | grep \"asn\"          | awk -F '"' '{print $4}' ) 2>/dev/null
    [[ $cityyyy == Singapore ]] && unset cityyyy
    [[ -z $isppppp ]] && isp="No ISP detected"
    [[ -z $asnnnnn ]] && isp="No ASN detected"
}

ip_ipinfo_aniverse() {
    mkdir -p $HOME/.abench
    wget -t1 -T6 -qO- ipinfo.io > $HOME/.abench/ipinfo 2>&1
    asnnnnn="$(cat $HOME/.abench/ipinfo | grep \"org\"      | awk -F '"' '{print $4}')"
    cityyyy="$(cat $HOME/.abench/ipinfo | grep \"city\"     | awk -F '"' '{print $4}')"
    country="$(cat $HOME/.abench/ipinfo | grep \"country\"  | awk -F '"' '{print $4}')"
    regionn="$(cat $HOME/.abench/ipinfo | grep \"region\"   | awk -F '"' '{print $4}')"
    [[ $cityyyy == Singapore ]] && unset cityyyy
    [[ -z $asnnnnn ]] && isp="No ASN detected"
}

# bench.sh
# wget -q -T10 -O- ipinfo.io
# wget -q -T10 -O- ipinfo.io/5.9.5.5/org
ip_ipinfo() {
    local org="$(wget -q -T10 -O- ipinfo.io/org)"
    local city="$(wget -q -T10 -O- ipinfo.io/city)"
    local country="$(wget -q -T10 -O- ipinfo.io/country)"
    local region="$(wget -q -T10 -O- ipinfo.io/region)"
    [[ -n "$org" ]] && echo " Organization          : $(echo "$org")"
    [[ -n "$city" && -n "$country" ]] && echo " Location              : $(echo "$city / $country")"
    [[ -n "$region" ]] && echo " Region                : $(echo "$region")"
}




################################################################################################
################################################################################################ Shared-Seedbox
################################################################################################




seedbox_neighbors_check() {
    echo -e "${bold}正在检查盒子的邻居情况 ...${normal}"
    cd $HOME
    current_disk=$(echo $(pwd) | sed "s/\/$(whoami)//")  # 下边我写重复，其实主要目的是为了在注释里写一下各种共享盒子的路径是什么样子的格式
    [[ $Seedbox == USB    ]] && current_disk=$(echo $(pwd) | sed "s/\/$(whoami)//") # /home11     这样子的
    [[ $Seedbox == PM     ]] && current_disk=$(echo $(pwd) | sed "s/\/$(whoami)//") # /home       这样子的
    [[ $Seedbox == SH     ]] && current_disk=$(echo $(pwd) | sed "s/\/$(whoami)//") # /home22     这样子的
    [[ $Seedbox == FH     ]] && current_disk=$(echo $(pwd) | sed "s/\/$(whoami)//") # /media/sdk1 这样子的，或者 /media/98811
    [[ $Seedbox == DSD    ]] && current_disk=$(echo $(pwd) | sed "s/\/$(whoami)//") # /       这样子的
    [[ $Seedbox == Sbcc   ]] && current_disk=$(echo $(pwd) | sed "s/\/$(whoami)//") # /home/user  这样子的
    [[ $Seedbox == AppBox ]] && [[ $(whoami) != root  ]] && current_disk=/home/$(whoami)
    [[ $Seedbox == AppBox ]] && [[ $(whoami) == root  ]] && current_disk=/root
    # /media/sdr1/home 这样子的，一些老的 FH HDD 会出现这样的
    [[ $Seedbox == FH  ]] && echo $current_disk | grep -q "/home" && current_disk=$(echo $current_disk | sed "s/\/home//") && FH_HOME=1

    # 所有邻居
    getent passwd | grep -Ev "$(whoami)|root" | grep -E "/bin/sh|/bin/bash" | grep -E "home|home[0-9]+|media" > $HOME/.abench/neighbors_all

    neighbors_all_num=$(cat $HOME/.abench/neighbors_all | wc -l)
    neighbors_same_disk_num=$(cat $HOME/.abench/neighbors_all | grep "$current_disk/" | wc -l)
    # grep "$current_disk/" 是为了防止 current_disk=/home1 时，把 /home11 这些也算进来

    if [[ $FH_SSD == 1 ]];then
        current_disk_size=($( LANG=C df -hPl | grep $(pwd) | awk '{print $2}' ))
        current_disk_total_used=($( LANG=C df -hPl | grep $(pwd) | awk '{print $3}' ))
        current_disk_self_used=$( du -sh $HOME 2>&1 | awk -F " " '{print $1}' )
    else
        current_disk_size=($( LANG=C df -hPl | grep $current_disk | awk '{print $2}' ))
        current_disk_total_used=($( LANG=C df -hPl | grep $current_disk | awk '{print $3}' ))
        current_disk_self_used=$( du -sh $HOME 2>&1 | awk -F " " '{print $1}' )
    fi
    # current_disk_avai=($( LANG=C df -hPl | grep $current_disk | awk '{print $4}' ))
    # current_disk_perc=($( LANG=C df -hPl | grep $current_disk | awk '{print $5}' ))
}


seedbox_check() {
    serverfqdn=$( hostname -f 2>&1 )
    [ -z $serverfqdn ] && serverfqdn=$( hostname 2>&1 )

    Seedbox=Unknown
    echo $serverfqdn | grep -q feral          && Seedbox=FH
    echo $serverfqdn | grep -q seedhost       && Seedbox=SH
    echo $serverfqdn | grep -q pulsedmedia    && Seedbox=PM
    echo $serverfqdn | grep -q ultraseedbox   && Seedbox=USB ; echo $serverfqdn | grep -qi usb && Seedbox=USB
    echo $serverfqdn | grep -q appbox         && Seedbox=AppBox && Docker=1
    echo $serverfqdn | grep -q seedboxes.cc   && Seedbox=Sbcc   && Docker=1
    # 2020.04.11 FH SSD 作特殊处理的原因是，大概 19 年开始 FH SSD 严格限制硬盘占用，每个用户都会在 df -h 下边有独立的空间显示，这就导致脚本计算硬盘大小的时候容量是实际的 2 倍左右
    # 不过我是很久没买过了，不知道现在是不是还是这样
    [[ $Seedbox == FH ]] && df -hPl | grep -q "/media/md" && FH_SSD=1
    [[ $debug == 1 ]] && echo -e "Seedbox=$Seedbox  FH_SSD=$FH_SSD"

    df -hPl | grep -wvP '\-|none|tmpfs|devtmpfs|by-uuid|chroot|Filesystem|udev|docker|md[0-9]+/[a-z].*' | sort -u > $HOME/.abench/par_list

    if [[ ! $Seedbox == Unknown ]] && [[ ! $EUID = 0 ]] && [[ $virtual != Docker ]]; then
        seedbox_neighbors_check
    fi
}


################################################################################################
################################################################################################ IO Test
################################################################################################



# https://github.com/n-st/nench
Bps_to_MiBps()   { awk '{ printf "%.2f MiB/s\n", $0 / 1024 / 1024 } END { if (NR == 0) { print "error" } }' ; }
Bps_to_MBps()    { awk '{ printf "%.0f MB/s\n", $0 / 1000 / 1000  } END { if (NR == 0) { print "error" } }' ; }
Bps_to_MBps_1f() { awk '{ printf "%.1f MB/s\n", $0 / 1000 / 1000  } END { if (NR == 0) { print "error" } }' ; }
dd_benchmark()   {
    LC_ALL=C dd if=/dev/zero of=test_$$ bs=64k count=16k conv=fdatasync 2>&1 | awk -F, '
        { io=$NF ; }
        END { if (io ~ /TB\/s/) {printf("%.0f\n", 1000*1000*1000*1000*io)}
        else if (io ~ /GB\/s/) {printf("%.0f\n", 1000*1000*1000*io)}
        else if (io ~ /MB\/s/) {printf("%.0f\n", 1000*1000*io)}
        else if (io ~ /KB\/s/) {printf("%.0f\n", 1000*io)}
        else { printf("%.0f", 1*io)} ; }'
    rm -f test_$$
}



################################################################################################
################################################################################################ Network test
################################################################################################
# https://install.speedtest.net/ooklaserver/ooklaserver.sh



# These codes are from bench.sh
################################################################################################

# https://www.speedtest.net/apps/cli
install_speedtest_cli_offical() {
    if  ! has_cmd speedtest ; then
        wget --no-check-certificate -T10 -qO speedtest.tgz https://cdn.jsdelivr.net/gh/oooldking/script@1.1.7/speedtest_cli/ookla-speedtest-1.0.0-$(uname -m)-linux.tgz
        [ $? -ne 0 ] && echo -e "Error: Failed to download speedtest cli.\n" && exit 1
        if [[ $EUID == 0 ]]; then
            speedtest_cmd=/usr/local/bin/speedtest
        else
            speedtest_cmd=$HOME/.abench/bin/speedtest
            mkdir -p $HOME/.abench/bin $HOME/.abench/speedtest
            echo $PATH | grep -q $HOME/.abench/bin || export PATH=$HOME/.abench/bin:$PATH
        fi
        mkdir -p speedtest-cli && tar zxf speedtest.tgz -C ./speedtest-cli && chmod +x ./speedtest-cli/speedtest
        cp -f ./speedtest-cli/speedtest $speedtest_cmd
        rm -f speedtest.tgz ./speedtest-cli
    fi
}

speedtest_offical_cli_teddysun() {
    mkdir -p $HOME/.abench/speedtest
    local nodeName="$2"
    [ -z "$1" ] && speedtest --progress=no --accept-license --accept-gdpr > $HOME/.abench/speedtest/speedtest.log 2>&1 || \
    speedtest --progress=no --server-id=$1 --accept-license --accept-gdpr > $HOME/.abench/speedtest/speedtest.log 2>&1
    if [ $? -eq 0 ]; then
        local dl_speed=$(awk '/Download/{print $3" "$4}' $HOME/.abench/speedtest/speedtest.log)
        local up_speed=$(awk '/Upload/{print   $3" "$4}' $HOME/.abench/speedtest/speedtest.log)
        local  latency=$(awk '/Latency/{prin t $2" "$3}' $HOME/.abench/speedtest/speedtest.log)
        if [[ -n "${dl_speed}" && -n "${up_speed}" && -n "${latency}" ]]; then
            printf "\033[0;33m%-18s\033[0;32m%-18s\033[0;31m%-20s\033[0;36m%-12s\033[0m\n" " ${nodeName}" "${up_speed}" "${dl_speed}" "${latency}"
        fi
    fi
}

speedtest_teddysun() {
    printf "%-18s%-18s%-20s%-12s\n" " Node Name" "Upload Speed" "Download Speed" "Latency"
    speedtest_offical_cli_teddysun ''      'Speedtest.net'
    speedtest_offical_cli_teddysun '5145'  'Beijing    CU'
    speedtest_offical_cli_teddysun '3633'  'Shanghai   CT'
    speedtest_offical_cli_teddysun '24447' 'Shanghai   CU'
    speedtest_offical_cli_teddysun '27594' 'Guangzhou  CT'
    speedtest_offical_cli_teddysun '26678' 'Guangzhou  CU'
    speedtest_offical_cli_teddysun '16192' 'Shenzhen   CU'
    speedtest_offical_cli_teddysun '4515'  'Shenzhen   CM'
    speedtest_offical_cli_teddysun '32155' 'Hongkong   CN'
    speedtest_offical_cli_teddysun '13623' 'Singapore  SG'
    speedtest_offical_cli_teddysun '15047' 'Tokyo      JP'
}

# install_speedtest_cli_offical && speedtest_teddysun && rm -fr speedtest-cli
################################################################################################

################################################################################################
################################################################################################ Disk check
################################################################################################



function get_app_static () {
    local app=$1
    if [[ ! $app =~ (smartctl|ioping|iperf3|fio) ]]; then
        echo -e "ERROR: Only smartctl / ioping / iperf3 / fio is supported"
    fi
    arch=$(uname -m 2>&1)
    if [[ $arch == x86_64 ]]; then
        if [[ $EUID == 0 ]]; then
            app_cmd=/usr/local/bin/$app
        else
            app_cmd=$HOME/.abench/bin/$app
            mkdir -p $HOME/.abench/bin
            echo $PATH | grep -q $HOME/.abench/bin || export PATH=$HOME/.abench/bin:$PATH
        fi
        if   [[ $app == smartctl ]] && [[ ! -x $app_cmd ]]; then
            echo -e "Installing $app static builds to $app_cmd ..."
            wget https://raw.githubusercontent.com/BlueSkyXN/ChangeSource/master/inexistence/inexistence-files/binary/amd64/$app -qO $app_cmd
            chmod 755 $app_cmd
        elif [[ $app != smartctl ]] && [[ -z $(which $app) ]]; then
            echo -e "Installing $app static builds to $app_cmd ..."
            wget https://raw.githubusercontent.com/BlueSkyXN/ChangeSource/master/inexistence/inexistence-files/binary/amd64/$app -qO $app_cmd
            chmod 755 $app_cmd
        fi
    else
        echo -e "ERROR: Only amd64 architecture is supported when using static builds"
    fi
}

function grep_power_on_hours () {
    while read line ; do echo "$line" | grep Power_On_Hours | awk '{if (index($10, "h") > 0) {print substr($10, 1, index($10, "h") -1)} else print $10}' ; done
}

function grep_disk_model () {
    while read line ; do echo "$line" | grep "Device Model" | sed "s/Device Model[:]\?//" | awk '{print $1,$2,$3,$4}' ; done
}

function write_disk_info () {
    echo "$num text $power_on_hours $model" >> $HOME/.abench/disk.info
}

# smartctl -d test /dev/sg0
# Origin code from https://github.com/dave-pl/hwcheck
function disk_check_smart () {
    case "$raidcard" in
        NoRaid      )   disk=$(fdisk -l 2>/dev/null| grep -i dev |egrep -v "(/dev/[brm])"| awk '/:/ {print $2}'| cut -f 1 -d ":") ; d=0
                        for i in $disk; do
                            if [[ $( smartctl -a $i | grep_power_on_hours) ]]; then
                                d=$(expr $d + 1)
                                num="disk-$d"
                                power_on_hours=$(smartctl -a $i | grep_power_on_hours)
                                model=$(smartctl -a $i | grep "Device Model"| grep -vi qemu | sed "s/Device Model[:]\?//" | awk '{print $1,$2,$3,$4}')
                                write_disk_info
                            fi
                        done
                        ;;
        MegaRAID    )   for i in `seq 0 99` ; do
                            if [[ $( smartctl -a -d megaraid,$i /dev/sg0 | grep_power_on_hours ) ]]; then
                                num="disk-$(expr $i + 1)"
                                power_on_hours=$(smartctl -a -d megaraid,$i /dev/sg0 | grep_power_on_hours)
                                model=$(smartctl -a -d megaraid,$i /dev/sg0 | grep_disk_model)
                                write_disk_info
                            fi
                         done
                        ;;
        HP-RAID     )   for i in `seq 0 99` ; do
                            if [[ $( smartctl -a -d cciss,$i /dev/sg0 | grep_power_on_hours ) ]]; then
                                num="disk-$(expr $i + 1)"
                                power_on_hours=$(smartctl -a -d cciss,$i /dev/sg0 | grep_power_on_hours)
                                model=$(smartctl -a -d cciss,$i /dev/sg0 | grep_disk_model)
                                write_disk_info
                            fi
                        done
                        ;;
        SCSI|Adaptec)   disk=$(find /dev -name sg*) ; d=0 # 其实 NoRAID 也可以用这个办法
                        for i in $disk ; do
                            if [[ $( smartctl -a $i | grep_power_on_hours ) ]]; then
                                d=$(expr $d + 1)
                                num="disk-$d"
                                power_on_hours=$(smartctl -a $i | grep_power_on_hours)
                                model=$(smartctl -a $i | grep_disk_model)
                                write_disk_info
                            fi
                        done
                        ;;
        NVMe        )   disk=$(find /dev -name nvme*n1) ; d=0
                        for i in $disk ; do
                            if [[ $( smartctl -a $i 2>&1 | grep -i "Power.On.Hours" | awk '{print $NF}' | sed "s|,||" ) ]]; then
                                d=$(expr $d + 1)
                                num="disk-$d"
                                power_on_hours=$(smartctl -a $i 2>&1 | grep -i "Power.On.Hours" | awk '{print $NF}' | sed "s|,||")
                                model=$(smartctl -a $i | grep -i Model | sed "s/Model.*://" | awk '{print $1,$2,$3,$4}')
                                write_disk_info
                        #   if [[ $( nvme smart-log $i 2>&1 | grep power_on_hours ) ]]; then
                        #       num="disk-$(expr $i + 1)"
                        #       power_on_hours=$(nvme smart-log $i | grep power_on_hours | grep -oE "[0-9,]+" | sed "s/,//")
                        #       model=$(nvme id-ctrl $i | grep -w mn | awk -F':' '{print $2,$3,$4}' | sed 's/^ //')
                        #       write_disk_info
                            fi
                        done
                        ;;
    esac
}


function disk_check_raid () {
    [[ $debug == 1 ]] && lspci | grep -E "RAID|SCSI|SATA"
    if [[ -n `lspci|grep -i "RAID bus controller"|grep "MegaRAID"` ]]; then
        raidcard=MegaRAID
        RC_Model="$(lspci|grep -i "RAID bus controller"|grep "MegaRAID" | awk -F ":" '{print $3}' | sed "s/^ //")"
    elif [[ -n `lspci|grep -i "RAID bus controller"|grep "Hewlett-Packard"` ]]; then
        raidcard=HP-RAID
        RC_Model="$(lspci|grep -i "RAID bus controller"|grep "Hewlett-Packard" | awk -F ":" '{print $3}' | sed "s/^ //")"
    elif [[ -n `lspci|grep -i "RAID bus controller"|grep "Adaptec"` ]]; then
        raidcard=Adaptec
    elif [[ -n `lspci|grep -i "SCSI controller"` ]]; then
        raidcard=SCSI
        RC_Model="$(lspci|grep -i "SCSI controller" | awk -F ":" '{print $3}' | sed "s/^ //")"
    elif [[ -n $(fdisk -l 2>/dev/null|grep /dev/nvme) ]]; then
        raidcard=NVMe
    else
        raidcard=NoRaid # 其实还有很多种情况检测不到的，不管了
    fi
    disk_check_smart
    if [[ $raidcard == NVMe ]]; then
        raidcard=NoRaid && disk_check_smart
    fi
    [[ $debug == 1 ]] && echo -e "raidcard=$raidcard" && cp -f  $HOME/.abench/disk.info  $HOME/disk-info-debug
}


function disk_check_no_root () {
    Raid=No
    # ls /dev/disk/by-id 2>/dev/null | grep -q scsi- && Raid=Hard
    # NVMe 目前不支持
    ls /dev/disk/by-id 2>/dev/null | grep -q md-   && Raid=Soft

    [[ $debug == 1 ]] && echo -e "Raid=$Raid"
    [[ $Raid != Hard ]] && ls /dev/disk/by-id 2>/dev/null | grep -oE "ata-.*" | sed "s/ata-//" | sed "s/-part.*//" | grep -oE "[a-zA-Z0-9_-]+" | grep -v 0m | sort -u | grep -vi qemu > $HOME/.abench/disk.info

    if [[ $virtual == Docker ]] || [[ $Seedbox == FH ]]; then
        lsblk --nodeps --noheadings --output MODEL --exclude 1,2,11 > $HOME/.abench/disk.info
        cat $HOME/.abench/disk.info | grep -q LSI && rm -f $HOME/.abench/disk.info && touch $HOME/.abench/disk.info
        cat $HOME/.abench/disk.info | grep -qE "MR[0-9]+-" && rm -f $HOME/.abench/disk.info && touch $HOME/.abench/disk.info
        cat $HOME/.abench/disk.info | grep -qi RAID && rm -f $HOME/.abench/disk.info && touch $HOME/.abench/disk.info
        cat $HOME/.abench/disk.info | grep -q "LOGICAL VOLUME" && rm -f $HOME/.abench/disk.info && touch $HOME/.abench/disk.info  # OP 10欧 HP
        cat $HOME/.abench/disk.info | grep -q "Virtual Disk" && rm -f $HOME/.abench/disk.info && touch $HOME/.abench/disk.info    # OP 10欧 DELL
        # 这里我也不知道有多少种情况，乱写了
        # MegaRAID 这个在 seedboes.cc（MR9271-8iCC）、Hz 16TB HWR（MR9260-4i）上测试通过
    fi

    cat $HOME/.abench/disk.info 2>/dev/null | sed -e 's/\(.*\)_/\1:/' | sed "s/:.*//" | sort -u > $HOME/.abench/disk.info.2
    # disk_num=$( cat $HOME/.abench/disk.info 2>/dev/null | wc -l )
    disk_num=$( lsblk --nodeps --noheadings --output NAME,SIZE,ROTA --exclude 1,2,11 2>&1 | wc -l )
    [[ $debug == 1 ]] && echo -e "disk_num=$disk_num"
    disk_model_num=$( cat $HOME/.abench/disk.info.2 2>/dev/null | wc -l )
    [[ $debug == 1 ]] && echo -e "\n" && cat $HOME/.abench/disk.info.2 && echo -e "\n"
    
    disk_model_1_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '1p')"  2>/dev/null | wc -l )
    disk_model_2_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '2p')"  2>/dev/null | wc -l )
    disk_model_3_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '3p')"  2>/dev/null | wc -l )
    disk_model_4_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '4p')"  2>/dev/null | wc -l )
    disk_model_5_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '5p')"  2>/dev/null | wc -l )
    disk_model_6_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '6p')"  2>/dev/null | wc -l )
    disk_model_7_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '7p')"  2>/dev/null | wc -l )
    disk_model_8_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '8p')"  2>/dev/null | wc -l )
    disk_model_9_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '9p')"  2>/dev/null | wc -l )
    disk_model_0_num=$( cat $HOME/.abench/disk.info 2>/dev/null | grep "$(cat $HOME/.abench/disk.info.2 2>/dev/null | sed -n '10p')" 2>/dev/null | wc -l )

    [[ $debug == 1 ]] && echo -e "disk_model_1_num=$disk_model_1_num"
    [[ $debug == 1 ]] && echo -e "disk_model_2_num=$disk_model_2_num"
}



################################################################################################
################################################################################################ deprecated
################################################################################################



check_release() {
    if [ -f /etc/redhat-release ]; then
        release="centos"
    elif cat /etc/issue | grep -Eqi "debian"; then
        release="debian"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -Eqi "debian"; then
        release="debian"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
    elif cat /etc/os-release | grep -Eqi "arch.linux" ; then
        release="archlinux"
    elif cat /etc/os-release | grep -Eqi "slackware" ; then
        release="slackware"
    fi
}

deprecated_disk_check() {
    # 其实这个判定对于独服可能不太对
    # disk_par_num=$(df -lh | grep -P "/home[0-9]+|media|home|mnt" | wc -l)
    disk_par_num=$(cat $HOME/par_list | wc -l)
    # 这个估计没毛病，Docker、独服、KVM 下都没问题的样子，别的不知道
    # disk_par_num=$(lsblk --nodeps --noheadings --output NAME,SIZE,ROTA --exclude 1,2,11 2>&1 | wc -l)

    # / 为最大分区时，数字 +1
    [[ $(df -lh | grep $(df -k | sort -rn -k4 | awk '{print $1}' | head -1) | awk '{print $NF}') == / ]] && disk_par_num=$(expr $disk_par_num + 1)

    # lsblk --exclude 1,2,11 --output NAME,SIZE,ROTA,TYPE,MOUNTPOINT,MODEL
    # lsblk -dno MODEL 2>&1 | sort | uniq -c | sort -nr              | awk '{printf("共 %-2s 块 %s %s %s %s\n", $1, $2, $3, $4, $5)}'
    # lsblk -dno MODEL 2>&1 | sort -u
    # lsblk --nodeps --exclude 1,2,11 --output NAME,SIZE,ROTA,MODEL | awk '{if ($3 == 0) {$3=" SSD"} if ($3 == 1) {$3=" HDD"} ; printf("%-5s%7s%5s   %s %s %s %s\n", $1, $2, $3, $4, $5, $6, $7)}' | sed "s|ROTA|TYPE|" | awk 'NR==1 {print $0};NR!=1 {print $0 | "sort -n -k2"}'

    # disk_size=$(lsblk --nodeps --noheadings --output SIZE 2>&1 | awk '{print $1}')
    # disk_total_size=$( calc_disk ${disk_size[@]} )
    # disk_used_size=$( du -sh $HOME 2>&1 | awk -F " " '{print $1}' | sed "s/G//" )

    # 2020.02.28 lsblk／fdisk -l 计算硬盘空间的好处是，一些没格式化或者没挂载的硬盘也能算出来，但是还是容易出错
    # 下边这个是各类 bench 脚本通用的，还是用这个算了，起码算错了也没什么大不了的，因为大家都错了……

    # superbench
    # disk_size1=($( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|overlay|shm|udev|devtmpfs|by-uuid|chroot|Filesystem' | awk '{print $2}' ))
    # bench.sh
    # disk_size1=($( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|devtmpfs|by-uuid|chroot|Filesystem|udev|docker' | awk '{print $2}' ))

    # nvme list | grep /dev/nvme$i | sed "s/\b \b/_/g" | awk '{print $3}' | sed "s/_/ /g"
    # udevadm info --name=/dev/nvme${i}n1 | grep "disk/by-id/nvme-" | head -1 | sed "s|S: disk/by-id/nvme-||" | awk -F '_' '{print $1,$2}'
    # nvme_model=$(nvme list | grep /dev/nvme$i | sed "s/\b \b/_/g" | awk '{print $3}' | sed "s/_/ /g")
    # nvme_model="$(smartctl -a /dev/nvme${i}n1 | grep "Model Number:" | cut -d ":" -f 2 | sed -e 's/^[ \t]*//')"
}

deprecated_interface_check() {
    # LotServer
    [ -n "$(grep 'eth0:' /proc/net/dev)" ] && wangka=eth0 || wangka=`cat /proc/net/dev |awk -F: 'function trim(str){sub(/^[ \t]*/,"",str); sub(/[ \t]*$/,"",str); return str } NR>2 {print trim($1)}'  |grep -Ev '^lo|^sit|^stf|^gif|^dummy|^vmnet|^vir|^gre|^ipip|^ppp|^bond|^tun|^tap|^ip6gre|^ip6tnl|^teql|^venet|^veth|^he-ipv6|^docker' |awk 'NR==1 {print $0}'`

    # swizzin
    wangka1=$(ip link show 2>&1 | grep -i broadcast | grep -m1 UP   | cut -d: -f 2 | cut -d@ -f 1 | sed 's/ //g')
    wangka2=$(ip link show 2>&1 | grep -i broadcast | grep -e MASTER| cut -d: -f 2 | cut -d@ -f 1 | sed 's/ //g')
    interface=${wangka1[0]} ; [[ -n $wangka2 ]] && interface=$wangka2
}

disk_check_dn_ver() {
    disknumber=1
    diskname=$(lsblk -p | grep disk | sed -n "$disknumber"p | awk '{print $1}')
    echo -n '' > /tmp/diskinfo
    while [[ $diskname != "" ]]; do
        echo $diskname >> /tmp/diskinfo
        ((disknumber = disknumber + 1))
        diskname=$(lsblk -p | grep disk | sed -n "$disknumber"p | awk '{print $1}')
    done
    ((disknumber = disknumber - 1))
    echo "一共 $disknumber 块硬盘"
    cat /tmp/diskinfo
    rm -f /tmp/diskinfo
}

################################################################################################
################################################################################################ deprecated - check ip info
################################################################################################

# This function doesn't work anymore
ip_ipip() {
    echo -e "${bold}正在检查服务器的其他 IP 信息 ... (可能要很久)${normal}"
    ipip_result=$HOME/ipip_result
    wget --no-check-certificate -qO- https://www.ipip.net/ip.html > $ipip_result 2>&1
    ipip_IP=$(   cat $ipip_result | grep -A3 IP     | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1 )
    ipip_ASN=$(  cat $ipip_result | grep -C7 ASN    | grep -oE "AS[0-9]+" | head -1 )
    ipip_CIDR=$( cat $ipip_result | grep -C15 CIDR | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" | head -1 )
    ipip_AS=$(   cat $ipip_result | grep -A1 $ipip_CIDR | grep -v $ipip_CIDR | grep -o "$ipip_ASN.*</a" | cut -d '>' -f2 | cut -d '<' -f1 )
    ipip_rDNS=$( cat $ipip_result | grep -oE "rDNS: [a-zA-Z0-9.-]+" | sed "s/rDNS: //" )
    ipip_Loc=$(  cat $ipip_result | grep -A10 "https://tools.ipip.net/traceroute.php?ip=" | grep 720px | grep -oE ">.*<" | sed "s/>//" | sed "s/<//" )
    ipip_ISP=$(  cat $ipip_result | grep "display: inline-block;text-align: center;width: 720px;float: left;line-height: 46px" | sed -n '2p' | grep -oE ">.*<" | sed "s/>//" | sed "s/<//" )
    rm -f $ipip_result
    # echo -e  "  反向域名              ${green}$ipip_rDNS${jiacu}"
    # echo -e  "  运营商                ${green}$ipip_ISP${jiacu}"
    # echo -e  "  AS  信息              ${green}$asnnnnn, $isppppp${jiacu}"
    # echo -e  "  地理位置              ${green}$ipip_Loc${jiacu}"
}

# Lack detail info
ip_mix() {
    echo -e "${bold}正在检查服务器的地理位置（可能不准） ...${normal}"
    result=$( wget -t1 -T10 -qO- http://freeapi.ipip.net/$serveripv4 )
    country=$( echo $result | awk -F '"' '{print $2}' )
    region=$( echo $result | awk -F '"' '{print $4}' )
    city=$( echo $result | awk -F '"' '{print $6}' )
    citydisplay=$( echo "$city, ")
    #isp=$( echo $result | awk -F '"' '{print $10}' )
    echo -e "${bold}正在检查服务器的 ISP ...${normal}"
    isp=$( wget --no-check-certificate -t1 -T10 -qO- https://ipapi.co/json | grep \"org\" | awk -F '"' '{print $4}' )
    echo -e "${bold}正在检查服务器的 ASN ...${normal}"
    asn=$(wget --no-check-certificate -t1 -T10 -qO- https://ipapi.co/asn/)
}

superbench_ip_info1() {
    # use jq tool
    result=$(curl -s 'http://ip-api.com/json')
    country=$(echo $result | jq '.country' | sed 's/\"//g')
    city=$(echo $result | jq '.city' | sed 's/\"//g')
    isp=$(echo $result | jq '.isp' | sed 's/\"//g')
    as_tmp=$(echo $result | jq '.as' | sed 's/\"//g')
    asn=$(echo $as_tmp | awk -F ' ' '{print $1}')
    org=$(echo $result | jq '.org' | sed 's/\"//g')
    countryCode=$(echo $result | jq '.countryCode' | sed 's/\"//g')
    region=$(echo $result | jq '.regionName' | sed 's/\"//g')
    if [ -n "$city" ]; then
        city=${region}
    fi

    echo -e " ASN & ISP            : ${cyan}$asn, $isp${normal}"
    echo -e " Organization         : ${yellow}$org${normal}"
    echo -e " Location             : ${cyan}$city, ${yellow}$country / $countryCode${normal}"
    echo -e " Region               : ${cyan}$region${normal}"
}

superbench_ip_info2() {
    # no jq
    country=$(curl -s https://ipapi.co/country_name/)
    city=$(curl -s https://ipapi.co/city/)
    asn=$(curl -s https://ipapi.co/asn/)
    org=$(curl -s https://ipapi.co/org/)
    countryCode=$(curl -s https://ipapi.co/country/)
    region=$(curl -s https://ipapi.co/region/)

    echo -e " ASN & ISP            : ${cyan}$asn${normal}"
    echo -e " Organization         : ${cyan}$org${normal}"
    echo -e " Location             : ${cyan}$city, ${GREEN}$country / $countryCode${normal}"
    echo -e " Region               : ${cyan}$region${normal}"
}

superbench_init(){
    if  [ ! -e './speedtest-cli/speedtest' ]; then
        echo " Installing Speedtest-cli ..."
        wget --no-check-certificate -qO speedtest.tgz https://cdn.jsdelivr.net/gh/oooldking/script@1.1.7/speedtest_cli/ookla-speedtest-1.0.0-$(uname -m)-linux.tgz > /dev/null 2>&1
    fi
    mkdir -p speedtest-cli && tar zxvf speedtest.tgz -C ./speedtest-cli/ > /dev/null 2>&1 && chmod a+rx ./speedtest-cli/speedtest
    if  [ ! -e 'tools.py' ]; then
        echo " Installing tools.py ..."
        wget --no-check-certificate https://cdn.jsdelivr.net/gh/oooldking/script@1.1.7/tools.py > /dev/null 2>&1
    fi
    chmod a+rx tools.py
    if  [ ! -e 'fast_com.py' ]; then
        echo " Installing Fast.com-cli ..."
        wget --no-check-certificate https://cdn.jsdelivr.net/gh/sanderjo/fast.com@master/fast_com.py > /dev/null 2>&1
        wget --no-check-certificate https://cdn.jsdelivr.net/gh/sanderjo/fast.com@master/fast_com_example_usage.py > /dev/null 2>&1
    fi
    chmod a+rx fast_com.py
    chmod a+rx fast_com_example_usage.py
}

superbench_ip_info4(){
    ip_date=$(curl -4 -s http://api.ip.la/en?json)
    echo $ip_date > ip_json.json
    isp=$(python tools.py geoip isp)
    as_tmp=$(python tools.py geoip as)
    asn=$(echo $as_tmp | awk -F ' ' '{print $1}')
    org=$(python tools.py geoip org)
    if [ -n "$ip_date" ]; then
        echo $ip_date
        echo "hala"
        country=$(python tools.py ipip country_name)
        city=$(python tools.py ipip city)
        countryCode=$(python tools.py ipip country_code)
        region=$(python tools.py ipip province)
    else
        country=$(python tools.py geoip country)
        city=$(python tools.py geoip city)
        countryCode=$(python tools.py geoip countryCode)
        region=$(python tools.py geoip regionName)  
    fi
    if [ -z "$city" ]; then
        city=${region}
    fi

    echo -e " ASN & ISP            : ${cyan}$asn, $isp${normal}"
    echo -e " Organization         : ${yellow}$org${normal}"
    echo -e " Location             : ${cyan}$city, ${yellow}$country / $countryCode${normal}"
    echo -e " Region               : ${cyan}$region${normal}"

    rm -rf tools.py
    rm -rf ip_json.json
}

ip_ipapi_2() {
    mkdir -p $HOME/.abench
    wget -t1 -T6 -qO- -4 'http://ip-api.com/json' | sed "s|,|\n|g" > $HOME/.abench/ip-api 2>&1
    country=$( cat $HOME/.abench/ip-api | grep \"country\"      | awk -F '"' '{print $4}' ) 2>/dev/null
    regionn=$( cat $HOME/.abench/ip-api | grep \"regionName\"   | awk -F '"' '{print $4}' ) 2>/dev/null
    cityyyy=$( cat $HOME/.abench/ip-api | grep \"city\"         | awk -F '"' '{print $4}' ) 2>/dev/null
    asnnnnn=$( cat $HOME/.abench/ip-api | grep \"as\"           | awk -F '"' '{print $4}' ) 2>/dev/null
    [[ $cityyyy == Singapore ]] && unset cityyyy
}
