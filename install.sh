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

########################
# Phân tích tham số
########################
VERSION_ARG=""
API_HOST_ARG=""
NODE_ID_ARG=""
API_KEY_ARG=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api-host)
                API_HOST_ARG="$2"; shift 2 ;;
            --node-id)
                NODE_ID_ARG="$2"; shift 2 ;;
            --api-key)
                API_KEY_ARG="$2"; shift 2 ;;
            -h|--help)
                echo "Cách dùng: $0 [phiên bản] [--api-host URL] [--node-id ID] [--api-key KEY]"
                exit 0 ;;
            --*)
                echo "Tham số không hợp lệ: $1"; exit 1 ;;
            *)
                if [[ -z "$VERSION_ARG" ]]; then
                    VERSION_ARG="$1"; shift
                else
                    shift
                fi ;;
        esac
    done
}

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

install_base() {
    need_install_apt() {
        local packages=("$@")
        local missing=()
        local installed_list=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Cài đặt gói thiếu: ${missing[*]}"
            apt-get update -y >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" >/dev/null 2>&1
        fi
    }

    need_install_yum() {
        local packages=("$@")
        local missing=()
        local installed_list=$(rpm -qa --qf '%{NAME}\n' 2>/dev/null | sort)
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Cài đặt gói thiếu: ${missing[*]}"
            yum install -y "${missing[@]}" >/dev/null 2>&1
        fi
    }

    need_install_apk() {
        local packages=("$@")
        local missing=()
        local installed_list=$(apk info 2>/dev/null | sort)
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Cài đặt gói thiếu: ${missing[*]}"
            apk add --no-cache "${missing[@]}" >/dev/null 2>&1
        fi
    }

    if [[ x"${release}" == x"centos" ]]; then
        if ! rpm -q epel-release >/dev/null 2>&1; then
            echo "Cài đặt nguồn EPEL..."
            yum install -y epel-release >/dev/null 2>&1
        fi
        need_install_yum wget curl unzip tar cronie socat ca-certificates pv
        update-ca-trust force-enable >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"alpine" ]]; then
        need_install_apk wget curl unzip tar socat ca-certificates pv
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"debian" ]]; then
        need_install_apt wget curl unzip tar cron socat ca-certificates pv
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"ubuntu" ]]; then
        need_install_apt wget curl unzip tar cron socat ca-certificates pv
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"arch" ]]; then
        echo "Cập nhật cơ sở dữ liệu gói..."
        pacman -Sy --noconfirm >/dev/null 2>&1
        echo "Cài đặt các gói cần thiết..."
        pacman -S --noconfirm --needed wget curl unzip tar cronie socat ca-certificates pv >/dev/null 2>&1
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

generate_z1server_config() {
        local api_host="$1"
        local node_id="$2"
        local api_key="$3"

        mkdir -p /etc/z1server >/dev/null 2>&1
        cat > /etc/z1server/config.json <<EOF
{
    "Log": {
        "Level": "warning",
        "Output": "",
        "Access": "none"
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
            echo -e "${red}Z1Server có thể đã khởi động thất bại, hãy dùng z1server log để xem nhật ký${plain}"
        fi
}

install_z1server() {
    local version_param="$1"
    if [[ -e /usr/local/z1server/ ]]; then
        rm -rf /usr/local/z1server/
    fi

    mkdir /usr/local/z1server/ -p
    cd /usr/local/z1server/

    if  [[ -z "$version_param" ]] ; then
        last_version=$(curl -Ls "https://api.github.com/repos/z1-benc/Z1-Server/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Không thể kiểm tra phiên bản Z1Server, có thể do vượt giới hạn API GitHub, vui lòng thử lại sau${plain}"
            exit 1
        fi
        echo -e "${green}Phát hiện phiên bản mới nhất: ${last_version}, bắt đầu cài đặt...${plain}"
        url="https://github.com/z1-benc/Z1-Server/releases/download/${last_version}/z1server-linux-${arch}.zip"
        curl -fSL "$url" | pv -s 30M -W -N "Đang tải" > /usr/local/z1server/z1server-linux.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Tải Z1Server thất bại, hãy đảm bảo server có thể tải file từ GitHub${plain}"
            rm -f /usr/local/z1server/z1server-linux.zip
            exit 1
        fi
    else
    last_version=$version_param
        url="https://github.com/z1-benc/Z1-Server/releases/download/${last_version}/z1server-linux-${arch}.zip"
        curl -fSL "$url" | pv -s 30M -W -N "Đang tải" > /usr/local/z1server/z1server-linux.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Tải Z1Server $1 thất bại, hãy đảm bảo phiên bản này tồn tại${plain}"
            rm -f /usr/local/z1server/z1server-linux.zip
            exit 1
        fi
    fi

    unzip z1server-linux.zip
    rm z1server-linux.zip -f
    chmod +x z1server
    mkdir /etc/z1server/ -p
    cp geoip.dat /etc/z1server/
    cp geosite.dat /etc/z1server/
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/z1server -f
        cat <<EOF > /etc/init.d/z1server
#!/sbin/openrc-run

name="z1server"
description="Z1Server"

command="/usr/local/z1server/z1server"
command_args="server"
command_user="root"

pidfile="/run/z1server.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/z1server
        rc-update add z1server default
        echo -e "${green}Z1Server ${last_version}${plain} đã cài đặt xong, đã bật tự khởi động cùng hệ thống"
    else
        rm /etc/systemd/system/z1server.service -f
        cat <<EOF > /etc/systemd/system/z1server.service
[Unit]
Description=Z1Server Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/z1server/
ExecStart=/usr/local/z1server/z1server server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop z1server
        systemctl enable z1server
        echo -e "${green}Z1Server ${last_version}${plain} đã cài đặt xong, đã bật tự khởi động cùng hệ thống"
    fi

    if [[ ! -f /etc/z1server/config.json ]]; then
        if [[ -n "$API_HOST_ARG" && -n "$NODE_ID_ARG" && -n "$API_KEY_ARG" ]]; then
            generate_z1server_config "$API_HOST_ARG" "$NODE_ID_ARG" "$API_KEY_ARG"
            echo -e "${green}Đã tạo /etc/z1server/config.json từ tham số${plain}"
            first_install=false
        else
            cp config.json /etc/z1server/
            first_install=true
        fi
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service z1server start
        else
            systemctl start z1server
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}Z1Server khởi động lại thành công${plain}"
        else
            echo -e "${red}Z1Server có thể đã khởi động thất bại, hãy dùng z1server log để xem nhật ký${plain}"
        fi
        first_install=false
    fi


    curl -o /usr/bin/z1server -fLs https://raw.githubusercontent.com/z1-benc/Z1-Server/main/z1server.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Tải script quản lý thất bại, thử sao chép trực tiếp...${plain}"
        if [[ -f /usr/local/z1server/script/z1server.sh ]]; then
            cp /usr/local/z1server/script/z1server.sh /usr/bin/z1server
        fi
    fi
    chmod +x /usr/bin/z1server

    cd $cur_dir
    rm -f install.sh
    echo "------------------------------------------"
    echo -e "Hướng dẫn sử dụng: "
    echo "------------------------------------------"
    echo "z1server              - Hiển thị menu quản lý"
    echo "z1server start        - Khởi động Z1Server"
    echo "z1server stop         - Dừng Z1Server"
    echo "z1server restart      - Khởi động lại Z1Server"
    echo "z1server status       - Xem trạng thái Z1Server"
    echo "z1server enable       - Bật tự khởi động"
    echo "z1server disable      - Tắt tự khởi động"
    echo "z1server log          - Xem nhật ký Z1Server"
    echo "z1server generate     - Tạo file cấu hình"
    echo "z1server update       - Cập nhật Z1Server"
    echo "z1server update x.x.x - Cập nhật phiên bản chỉ định"
    echo "z1server install      - Cài đặt Z1Server"
    echo "z1server uninstall    - Gỡ cài đặt Z1Server"
    echo "z1server version      - Xem phiên bản Z1Server"
    echo "------------------------------------------"

    if [[ $first_install == true ]]; then
        read -rp "Phát hiện đây là lần cài đặt đầu tiên, bạn có muốn tự động tạo /etc/z1server/config.json? (y/n): " if_generate
        if [[ "$if_generate" =~ ^[Yy]$ ]]; then
            read -rp "Địa chỉ API Panel [VD: https://example.com/]: " api_host
            api_host=${api_host:-https://example.com/}
            read -rp "Node ID: " node_id
            node_id=${node_id:-1}
            read -rp "Khóa liên lạc node: " api_key

            generate_z1server_config "$api_host" "$node_id" "$api_key"
        else
            echo "${green}Đã bỏ qua tạo cấu hình tự động. Để tạo sau, chạy: z1server generate${plain}"
        fi
    fi
}

parse_args "$@"
echo -e "${green}Bắt đầu cài đặt${plain}"
install_base
install_z1server "$VERSION_ARG"
