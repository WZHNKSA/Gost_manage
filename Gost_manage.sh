#!/bin/bash

# 关键参数
GOST_DIR="/root/apps/gost"
GOST_BIN="$GOST_DIR/gost"
SERVICE_DIR="/etc/systemd/system"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
NC='\033[0m'

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "错误：必须使用root权限运行此脚本！"
        exit 1
    fi
}

# 检查Gost安装状态
check_install_status() {
    if [ -f "$GOST_BIN" ]; then
        echo -e "[状态] Gost已安装 ${GREEN}●${NC}"
    else
        echo -e "[状态] Gost未安装 ${RED}●${NC}"
    fi
}

# 安装Gost
install_gost() {
    echo "正在安装Gost..."

    for cmd in wget tar gzip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "缺少依赖：$cmd，请先安装后再运行本脚本！"
            return 1
        fi
    done

    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        gost_pkg="gost_linux_amd64.tar.gz"
        download_url="https://pan.529808.xyz/index.php?explorer/share/file&hash=b26agum5EQjlpBJ8UMJM2PcvKFapy7Aj80k04lyejhE2EQwTAdWCuutfRDedjOuM62Tf"
    elif [[ "$arch" == "aarch64" ]] || [[ "$arch" == "arm64" ]]; then
        gost_pkg="gost_linux_arm64.tar.gz"
        download_url="https://pan.529808.xyz/index.php?explorer/share/file&hash=4c5b3BeiO_LAVTCl01U4e_8Wsowx4JNMR-OVGcMJIM3T7WurEl8fobk883_rBO6pz1G1"
    else
        echo "暂不支持的系统架构: $arch"
        return 1
    fi

    mkdir -p "$GOST_DIR"
    wget -O "$GOST_DIR/$gost_pkg" "$download_url"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络或下载链接！"
        return 1
    fi

    tar -xzvf "$GOST_DIR/$gost_pkg" -C "$GOST_DIR"
    if [ $? -ne 0 ]; then
        echo "解压失败！"
        rm -f "$GOST_DIR/$gost_pkg"
        return 1
    fi

    # 查找 gost 可执行文件并移动到 $GOST_BIN
    gost_bin=$(find "$GOST_DIR" -maxdepth 1 -type f -name 'gost*' -perm /u+x | head -n 1)
    if [ -z "$gost_bin" ]; then
        echo "未找到 gost 可执行文件！"
        return 1
    fi
    mv -f "$gost_bin" "$GOST_BIN"
    chmod +x "$GOST_BIN"

    rm -f "$GOST_DIR/$gost_pkg"
    echo "安装完成！Gost 路径: $GOST_BIN"
}

# 卸载Gost
uninstall_gost() {
    echo "正在卸载Gost..."
    rm -rf "$GOST_DIR"
    echo "卸载完成！"
}

# 统一编号并输出服务列表
list_services() {
    tunnel_services=($(systemctl list-unit-files --type=service --no-legend | grep '^gost_tunnel_' | awk '{print $1}' | sort))
    node_services=($(systemctl list-unit-files --type=service --no-legend | grep '^gost_node_' | awk '{print $1}' | sort))

    declare -gA SERVICE_MAP
    SERVICE_MAP=()
    index=0

    if [ ${#tunnel_services[@]} -gt 0 ]; then
        echo "所有隧道服务："
        for service in "${tunnel_services[@]}"; do
            key="t$index"
            SERVICE_MAP[$key]="$service"
            status=$(systemctl is-active "$service")
            color=$([ "$status" = "active" ] && echo "$GREEN" || echo "$RED")
            # 只保留用户输入部分
            service_name="${service#gost_tunnel_}"
            service_name="${service_name%.service}"
            echo -e "[$key] $service_name (状态: ${color}${status}${NC})"
            ((index++))
        done
    fi

    index=0
    if [ ${#node_services[@]} -gt 0 ]; then
        echo "所有节点服务："
        for service in "${node_services[@]}"; do
            key="s$index"
            SERVICE_MAP[$key]="$service"
            status=$(systemctl is-active "$service")
            color=$([ "$status" = "active" ] && echo "$GREEN" || echo "$RED")
            # 只保留用户输入部分
            service_name="${service#gost_node_}"
            service_name="${service_name%.service}"
            echo -e "[$key] $service_name (状态: ${color}${status}${NC})"
            ((index++))
        done
    fi

    if [ ${#tunnel_services[@]} -eq 0 ] && [ ${#node_services[@]} -eq 0 ]; then
        echo "当前没有任何隧道或节点服务"
        return 1
    fi
}

# 校验服务名
validate_name() {
    local name="$1"
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]
}

# 创建新服务
create_service() {
    read -p "请选择要创建的服务类型：
1. 创建加密隧道
2. 创建节点服务
请输入序号（1/2，默认 1）: " service_type
    service_type=${service_type:-1}

    case $service_type in
        1)
            read -p "请输入隧道名称（gost_tunnel_xx部分）: " tunnel_name
            if ! validate_name "$tunnel_name"; then
                echo "错误：名称只能包含字母、数字、下划线和中划线！"
                return
            fi
            service_file="$SERVICE_DIR/gost_tunnel_${tunnel_name}.service"
            if [ -f "$service_file" ]; then
                echo "错误：该名称的服务已存在！"
                return
            fi

            echo "请选择隧道类型："
            echo "1. 加密入口（本地监听TCP/UDP，转发至远程加密节点）"
            echo "2. 解密出口（本地监听relay+tls，负责解密并转发）"
            read -p "请输入序号（1/2，默认 1）: " tunnel_type
            tunnel_type=${tunnel_type:-1}

            case $tunnel_type in
                1)
                    read -p "请输入本地入口端口（TCP/UDP共用，例如 20001）: " local_port
                    if [ -z "$local_port" ]; then
                        echo "错误：入口端口不能为空！"
                        return
                    fi
                    read -p "请输入远程加密节点IP: " remote_ip
                    read -p "请输入远程加密节点端口: " remote_port
                    if [ -z "$remote_ip" ] || [ -z "$remote_port" ]; then
                        echo "错误：远程IP和端口不能为空！"
                        return
                    fi
                    gost_cmd="-L tcp://:$local_port -L udp://:$local_port -F relay+tls://$remote_ip:$remote_port"
                    ;;
                2)
                    read -p "是否转发到本机以外的IP？(Y/n): " forward_external
                    forward_external=${forward_external:-Y}
                    read -p "请输入本机解码端口（relay+tls监听端口，例如 30302）: " decode_port
                    if [ -z "$decode_port" ]; then
                        echo "错误：本机解码端口不能为空！"
                        return
                    fi
                    if [[ ! "$forward_external" =~ ^[Nn]$ ]]; then
                        # 默认为转发到外部
                        read -p "请输入目标服务器IP: " target_ip
                        read -p "请输入目标服务器端口: " target_port
                        if [ -z "$target_ip" ] || [ -z "$target_port" ]; then
                            echo "错误：目标服务器IP和端口不能为空！"
                            return
                        fi
                        gost_cmd="-L relay+tls://:$decode_port/$target_ip:$target_port"
                    else
                        gost_cmd="-L relay+tls://:$decode_port"
                    fi
                    ;;
                *)
                    echo "无效的选择！"
                    return
                    ;;
            esac

            cat > "$service_file" <<EOF
[Unit]
Description = gost tunnel (${tunnel_name})
After = network.target

[Service]
Type=simple
ExecStart=$GOST_BIN $gost_cmd
Restart = on-failure

[Install]
WantedBy = multi-user.target
EOF

            systemctl daemon-reload
            systemctl enable --now "gost_tunnel_${tunnel_name}.service"
            systemctl status "gost_tunnel_${tunnel_name}.service"
            ;;

        2)
            read -p "请输入节点名称（gost_node_xx部分）: " node_name
            if ! validate_name "$node_name"; then
                echo "错误：名称只能包含字母、数字、下划线和中划线！"
                return
            fi
            service_file="$SERVICE_DIR/gost_node_${node_name}.service"
            if [ -f "$service_file" ]; then
                echo "错误：该名称的服务已存在！"
                return
            fi

            echo "请选择节点服务类型："
            echo "1. shadowsocks"
            echo "2. socks5"
            read -p "请输入序号（1/2）: " node_type

            case $node_type in
                1)
                    echo "请选择加密方式："
                    echo "1. chacha20-ietf-poly1305"
                    echo "2. aes-256-gcm"
                    echo "3. aes-128-gcm"
                    read -p "请输入序号（1/2/3，默认 1）: " encrypt_type
                    encrypt_type=${encrypt_type:-1}
                    case $encrypt_type in
                        1) encrypt_method="chacha20-ietf-poly1305" ;;
                        2) encrypt_method="aes-256-gcm" ;;
                        3) encrypt_method="aes-128-gcm" ;;
                        *)
                            echo "无效的选择！"
                            return
                            ;;
                    esac
                    read -p "请输入密码: " password
                    if [ -z "$password" ]; then
                        echo "错误：密码不能为空！"
                        return
                    fi
                    read -p "请输入监听端口: " port
                    if [ -z "$port" ]; then
                        echo "错误：端口不能为空！"
                        return
                    fi
                    gost_cmd="-L ss://${encrypt_method}:${password}@:${port}"
                    ;;
                2)
                    read -p "是否需要用户名和密码认证？(Y/n): " need_auth
                    need_auth=${need_auth:-Y}
                    if [[ ! "$need_auth" =~ ^[Nn]$ ]]; then
                        read -p "请输入用户名: " socks_user
                        read -p "请输入密码: " socks_pass
                        if [ -z "$socks_user" ] || [ -z "$socks_pass" ]; then
                            echo "错误：用户名和密码不能为空！"
                            return
                        fi
                        read -p "请输入监听端口: " port
                        if [ -z "$port" ]; then
                            echo "错误：端口不能为空！"
                            return
                        fi
                        gost_cmd="-L socks5://$socks_user:$socks_pass@:$port?udp=true"
                    else
                        read -p "请输入监听端口: " port
                        if [ -z "$port" ]; then
                            echo "错误：端口不能为空！"
                            return
                        fi
                        gost_cmd="-L socks5://:$port?udp=true"
                    fi
                    ;;
                *)
                    echo "无效的选择！"
                    return
                    ;;
            esac

            cat > "$service_file" <<EOF
[Unit]
Description = gost node (${node_name})
After = network.target

[Service]
Type=simple
ExecStart=$GOST_BIN $gost_cmd
Restart = on-failure

[Install]
WantedBy = multi-user.target
EOF

            systemctl daemon-reload
            systemctl enable --now "gost_node_${node_name}.service"
            systemctl status "gost_node_${node_name}.service"
            ;;
        *)
            echo "无效的选择！"
            return
            ;;
    esac
}

# 统一编号解析
parse_choices() {
    local choices="$1"
    local -n out_arr=$2
    if [ "$choices" = "all" ]; then
        for key in "${!SERVICE_MAP[@]}"; do
            out_arr+=("$key")
        done
        return
    fi
    for choice in $choices; do
        if [[ "$choice" =~ ^[ts][0-9]+$ ]] && [ -n "${SERVICE_MAP[$choice]}" ]; then
            out_arr+=("$choice")
        else
            echo "序号 $choice 无效，跳过。"
        fi
    done
}

# 删除服务
delete_tunnel() {
    list_services || return
    read -p "请选择要删除的服务编号（如 t0 s1，可输入多个，用空格分隔，输入 all 删除全部）: " choices
    local selected=()
    parse_choices "$choices" selected
    if [ ${#selected[@]} -eq 0 ]; then
        echo "无效的选择！"
        return
    fi
    for key in "${selected[@]}"; do
        service="${SERVICE_MAP[$key]}"
        echo "正在停止并删除服务: $service"
        systemctl stop "$service"
        systemctl disable "$service"
        rm -f "$SERVICE_DIR/$service"
    done
    systemctl daemon-reload
    echo "已完成所选服务的删除操作"
}

# 启动服务
start_tunnel() {
    list_services || return
    read -p "请选择要启动的服务编号（如 t0 s1，可输入多个，用空格分隔，输入 all 启动全部）: " choices
    local selected=()
    parse_choices "$choices" selected
    if [ ${#selected[@]} -eq 0 ]; then
        echo "无效的选择！"
        return
    fi
    for key in "${selected[@]}"; do
        service="${SERVICE_MAP[$key]}"
        systemctl start "$service"
        echo "已启动服务: $service"
    done
}

# 停止服务
stop_tunnel() {
    list_services || return
    read -p "请选择要停止的服务编号（如 t0 s1，可输入多个，用空格分隔，输入 all 停止全部）: " choices
    local selected=()
    parse_choices "$choices" selected
    if [ ${#selected[@]} -eq 0 ]; then
        echo "无效的选择！"
        return
    fi
    for key in "${selected[@]}"; do
        service="${SERVICE_MAP[$key]}"
        systemctl stop "$service"
        echo "已停止服务: $service"
    done
}

# 重启服务
restart_tunnel() {
    list_services || return
    read -p "请选择要重启的服务编号（如 t0 s1，可输入多个，用空格分隔，输入 all 重启全部）: " choices
    local selected=()
    parse_choices "$choices" selected
    if [ ${#selected[@]} -eq 0 ]; then
        echo "无效的选择！"
        return
    fi
    for key in "${selected[@]}"; do
        service="${SERVICE_MAP[$key]}"
        systemctl restart "$service"
        echo "已重启服务: $service"
    done
}

# 查看服务日志
view_tunnel_log() {
    list_services || return
    read -p "请选择要查看日志的服务编号: " choice
    if [[ -z "$choice" || -z "${SERVICE_MAP[$choice]}" ]]; then
        echo "无效的选择！"
        return
    fi
    service="${SERVICE_MAP[$choice]}"
    journalctl -u "$service" -e
}

# 编辑服务配置
edit_tunnel_config() {
    list_services || return
    read -p "请选择要编辑的服务编号: " choice
    if [[ -z "$choice" || -z "${SERVICE_MAP[$choice]}" ]]; then
        echo "无效的选择！"
        return
    fi
    service="${SERVICE_MAP[$choice]}"
    nano "$SERVICE_DIR/$service"
    systemctl daemon-reload
    echo "已编辑并重载: $service"
}

# 备份所有服务配置
backup_configs() {
    backup_dir="$GOST_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    # 只备份以gost_tunnel_或gost_node_开头的服务文件
    find "$SERVICE_DIR" -maxdepth 1 -type f \( -name "gost_tunnel_*.service" -o -name "gost_node_*.service" \) -exec cp {} "$backup_dir" \;
    echo "已备份所有隧道和节点配置到: $backup_dir"
}

# 还原服务配置
restore_configs() {
    backup_folders=($(ls -dt "$GOST_DIR"/backup_* 2>/dev/null))
    if [ ${#backup_folders[@]} -eq 0 ]; then
        echo "未找到任何备份文件夹！"
        return
    fi
    echo "可用的备份文件夹："
    index=1
    for folder in "${backup_folders[@]}"; do
        echo "[$index] $(basename "$folder")"
        ((index++))
    done
    read -p "请输入要恢复的备份文件夹序号: " folder_choice
    if [[ ! "$folder_choice" =~ ^[0-9]+$ ]] || [ $folder_choice -lt 1 ] || [ $folder_choice -gt ${#backup_folders[@]} ]; then
        echo "无效的选择！"
        return
    fi
    selected_folder="${backup_folders[$((folder_choice-1))]}"
    files=($(ls "$selected_folder"/gost_*.service 2>/dev/null))
    if [ ${#files[@]} -eq 0 ]; then
        echo "该备份文件夹下没有可用的gost配置文件！"
        return
    fi
    echo "可恢复的配置文件列表："
    index=1
    for file in "${files[@]}"; do
        fname=$(basename "$file")
        echo "[$index] $fname"
        ((index++))
    done
    read -p "请输入要恢复的配置序号（可输入多个，用空格分隔，输入 all 恢复全部）: " choices
    if [ "$choices" = "all" ]; then
        cp "$selected_folder"/gost_*.service "$SERVICE_DIR"/
        systemctl daemon-reload
        echo "已恢复全部配置并重载 systemd"
        return
    fi
    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#files[@]} ]; then
            cp "${files[$((choice-1))]}" "$SERVICE_DIR"/
            echo "已恢复: $(basename "${files[$((choice-1))]}")"
        else
            echo "序号 $choice 无效，跳过。"
        fi
    done
    systemctl daemon-reload
    echo "已完成所选配置的恢复并重载 systemd"
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo "============ Gost管理脚本 ============"
        check_install_status
        list_services
        echo "--------------------------------------"
        echo "1. 安装Gost"
        echo "2. 卸载Gost"
        echo "3. 创建新服务"
        echo "4. 删除服务"
        echo "5. 启动服务"
        echo "6. 停止服务"
        echo "7. 重启服务"
        echo "8. 查看服务日志"
        echo "9. 编辑服务配置"
        echo "10. 备份所有服务配置"
        echo "11. 还原服务配置"
        echo "0. 退出"
        echo "======================================"
        read -p "请输入选择: " choice
        case $choice in
            1) install_gost ;;
            2) uninstall_gost ;;
            3) create_service ;;
            4) delete_tunnel ;;
            5) start_tunnel ;;
            6) stop_tunnel ;;
            7) restart_tunnel ;;
            8) view_tunnel_log ;;
            9) edit_tunnel_config ;;
            10) backup_configs ;;
            11) restore_configs ;;
            0) exit 0 ;;
            *) echo "无效的选择！" ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# 脚本入口
check_root
main_menu
