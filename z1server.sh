#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Lỗi:${plain} Phải chạy script bằng quyền root!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}Không phát hiện được phiên bản hệ điều hành!${plain}\n" && exit 1
fi

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}Không phát hiện được kiến trúc, dùng mặc định: ${arch}${plain}"
fi

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "Phần mềm không hỗ trợ hệ thống 32-bit, vui lòng dùng hệ thống 64-bit"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]+' '/VERSION_ID/{print $2}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Vui lòng dùng CentOS 7 trở lên!${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}Lưu ý: CentOS 7 không hỗ trợ giao thức hysteria1/2!${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Vui lòng dùng Ubuntu 16 trở lên!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Vui lòng dùng Debian 8 trở lên!${plain}\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [mặc định $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Có muốn khởi động lại Z1Server không?" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Nhấn Enter để quay lại menu chính: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/z1-benc/Z1-Server/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "Nhập phiên bản chỉ định (mặc định: mới nhất): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/z1-benc/Z1-Server/main/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}Cập nhật hoàn tất, Z1Server đã tự khởi động lại, dùng z1server log để xem nhật ký${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "Z1Server sẽ tự khởi động lại sau khi sửa cấu hình"
    nano /etc/z1server/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "Trạng thái Z1Server: ${green}Đang chạy${plain}"
            ;;
        1)
            echo -e "Z1Server chưa được khởi động hoặc khởi động lại thất bại, xem nhật ký? [Y/n]" && echo
            read -e -rp "(mặc định: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "Trạng thái Z1Server: ${red}Chưa cài đặt${plain}"
    esac
}

uninstall() {
    confirm "Bạn có chắc chắn muốn gỡ cài đặt Z1Server?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        service z1server stop
        rc-update del z1server
        rm /etc/init.d/z1server -f
    else
        systemctl stop z1server
        systemctl disable z1server
        rm /etc/systemd/system/z1server.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi
    rm /etc/z1server/ -rf
    rm /usr/local/z1server/ -rf

    echo ""
    echo -e "Gỡ cài đặt thành công! Nếu muốn xóa script, chạy: ${green}rm /usr/bin/z1server -f${plain}"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}Z1Server đã đang chạy, không cần khởi động lại${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service z1server start
        else
            systemctl start z1server
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}Z1Server khởi động thành công, dùng z1server log để xem nhật ký${plain}"
        else
            echo -e "${red}Z1Server có thể khởi động thất bại, dùng z1server log để xem nhật ký${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        service z1server stop
    else
        systemctl stop z1server
    fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}Z1Server đã dừng thành công${plain}"
    else
        echo -e "${red}Z1Server dừng thất bại, vui lòng xem nhật ký sau${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        service z1server restart
    else
        systemctl restart z1server
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}Z1Server khởi động lại thành công, dùng z1server log để xem nhật ký${plain}"
    else
        echo -e "${red}Z1Server có thể khởi động thất bại, dùng z1server log để xem nhật ký${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service z1server status
    else
        systemctl status z1server --no-pager -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add z1server
    else
        systemctl enable z1server
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}Z1Server đã bật tự khởi động thành công${plain}"
    else
        echo -e "${red}Z1Server bật tự khởi động thất bại${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del z1server
    else
        systemctl disable z1server
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}Z1Server đã tắt tự khởi động thành công${plain}"
    else
        echo -e "${red}Z1Server tắt tự khởi động thất bại${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}Alpine chưa hỗ trợ xem nhật ký${plain}\n" && exit 1
    else
        journalctl -u z1server.service -e --no-pager -f
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_shell() {
    wget -O /usr/bin/z1server -N --no-check-certificate https://raw.githubusercontent.com/z1-benc/Z1-Server/main/z1server.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}Tải script thất bại, hãy kiểm tra kết nối đến GitHub${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/z1server
        echo -e "${green}Nâng cấp script thành công, vui lòng chạy lại${plain}" && exit 0
    fi
}

# 0: đang chạy, 1: không chạy, 2: chưa cài đặt
check_status() {
    if [[ ! -f /usr/local/z1server/z1server ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service z1server status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status z1server | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show | grep z1server)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled z1server)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1;
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}Z1Server đã được cài đặt, không cần cài lại${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}Vui lòng cài đặt Z1Server trước${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "Trạng thái Z1Server: ${green}Đang chạy${plain}"
            show_enable_status
            ;;
        1)
            echo -e "Trạng thái Z1Server: ${yellow}Đã dừng${plain}"
            show_enable_status
            ;;
        2)
            echo -e "Trạng thái Z1Server: ${red}Chưa cài đặt${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Tự khởi động: ${green}Có${plain}"
    else
        echo -e "Tự khởi động: ${red}Không${plain}"
    fi
}

show_z1server_version() {
    echo -n "Phiên bản Z1Server: "
    /usr/local/z1server/z1server version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

generate_z1server_config() {
        local api_host="$1"
        local node_id="$2"
        local api_key="$3"

        mkdir -p /etc/z1server >/dev/null 2>&1
        cat > /etc/z1server/config.json <<EOF
{
    "Log": { "Level": "error" },
    "TargetCountry": "cn",
    "DnsServers": ["223.5.5.5", "1.1.1.1"],
    "EnableSniffing": true,
    "DeviceMinSpeed": 200,
    "Warp": {
        "Enable": true,
        "PrivateKey": "auto-generated",
        "Address": "172.16.0.2/32",
        "Reserved": [0, 0, 0]
    },
    "Nodes": [
        {
            "ApiHost": "${api_host}",
            "NodeID": ${node_id},
            "ApiKey": "${api_key}",
            "Timeout": 15
        }
    ]
}
EOF
        echo -e "${green}Đã tạo file cấu hình Z1Server, đang khởi động lại dịch vụ${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service z1server restart
        else
            systemctl restart z1server
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}Z1Server khởi động lại thành công${plain}"
        else
            echo -e "${red}Z1Server có thể đã khởi động thất bại, dùng z1server log để xem nhật ký${plain}"
        fi
}


generate_config_file() {
    read -rp "Địa chỉ API Panel [VD: https://example.com/]: " api_host
    api_host=${api_host:-https://example.com/}
    read -rp "Node ID: " node_id
    node_id=${node_id:-1}
    read -rp "Khóa liên lạc node: " api_key

    generate_z1server_config "$api_host" "$node_id" "$api_key"
}

# Mở tất cả cổng tường lửa
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}Đã mở tất cả cổng tường lửa thành công!${plain}"
}

show_usage() {
    echo "Hướng dẫn sử dụng Z1Server: "
    echo "------------------------------------------"
    echo "z1server              - Hiển thị menu quản lý"
    echo "z1server start        - Khởi động Z1Server"
    echo "z1server stop         - Dừng Z1Server"
    echo "z1server restart      - Khởi động lại Z1Server"
    echo "z1server status       - Xem trạng thái"
    echo "z1server enable       - Bật tự khởi động"
    echo "z1server disable      - Tắt tự khởi động"
    echo "z1server log          - Xem nhật ký"
    echo "z1server x25519       - Tạo khóa x25519"
    echo "z1server generate     - Tạo file cấu hình"
    echo "z1server update       - Cập nhật Z1Server"
    echo "z1server update x.x.x - Cập nhật phiên bản chỉ định"
    echo "z1server install      - Cài đặt Z1Server"
    echo "z1server uninstall    - Gỡ cài đặt Z1Server"
    echo "z1server version      - Xem phiên bản"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}Z1Server — Script quản lý backend,${plain} ${red}không dùng cho Docker${plain}
--- https://github.com/z1-benc/Z1-Server ---
  ${green}0.${plain} Sửa cấu hình
————————————————
  ${green}1.${plain} Cài đặt Z1Server
  ${green}2.${plain} Cập nhật Z1Server
  ${green}3.${plain} Gỡ cài đặt Z1Server
————————————————
  ${green}4.${plain} Khởi động Z1Server
  ${green}5.${plain} Dừng Z1Server
  ${green}6.${plain} Khởi động lại Z1Server
  ${green}7.${plain} Xem trạng thái Z1Server
  ${green}8.${plain} Xem nhật ký Z1Server
————————————————
  ${green}9.${plain} Bật tự khởi động
  ${green}10.${plain} Tắt tự khởi động
————————————————
  ${green}11.${plain} Xem phiên bản Z1Server
  ${green}12.${plain} Nâng cấp script quản lý
  ${green}13.${plain} Tạo file cấu hình Z1Server
  ${green}14.${plain} Mở tất cả cổng mạng VPS
  ${green}15.${plain} Thoát
 "
    show_status
    echo && read -rp "Nhập lựa chọn [0-15]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) check_install && show_z1server_version ;;
        12) update_shell ;;
        13) generate_config_file ;;
        14) open_ports ;;
        15) exit ;;
        *) echo -e "${red}Vui lòng nhập số hợp lệ [0-15]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "version") check_install 0 && show_z1server_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
