#!/bin/bash

GOST_DIR="/root/apps/gost"
SERVICE_DIR="/etc/systemd/system"

# 颜色定义
RED='\e[31m'
GREEN='\e[32m'
NC='\e[0m'

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "错误：必须使用root权限运行此脚本！"
        exit 1
    fi
}


# 检查Gost安装状态
check_install_status() {
    if [ -f "${GOST_DIR}/gost" ]; then
        echo -e "[状态] Gost已安装 ${GREEN}●${NC}"
    else
        echo -e "[状态] Gost未安装 ${RED}●${NC}"
    fi
}
# 安装Gost
install_gost() {
    echo "正在安装Gost..."

    # 检查依赖
    for cmd in wget tar gzip; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo "缺少依赖：$cmd，请先安装后再运行本脚本！"
            return 1
        fi
    done

    # 判断系统架构
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        gost_pkg="gost_linux_amd64.tar.gz"
        download_url="https://pan.529808.xyz/index.php?explorer/share/file&hash=7fa6a6TjMVXNWntMeDaZvTbT8y-ka3yJ80GehLxXHfsr1RzBEnPGcaFKINO2Svp474OE"
    elif [[ "$arch" == "aarch64" ]] || [[ "$arch" == "arm64" ]]; then
        gost_pkg="gost_linux_arm64.tar.gz"
        download_url="https://pan.529808.xyz/index.php?explorer/share/file&hash=25b35u8d0XOYO-AvcdrZWQ0sgGd4xOSb0EE61a2lUjtSipqIr4fXFxqIjRx6zjH3YIOF"
    else
        echo "暂不支持的系统架构: $arch"
        return 1
    fi

    mkdir -p $GOST_DIR

    # 下载 gost 压缩包到 GOST_DIR
    wget -O "$GOST_DIR/$gost_pkg" "$download_url"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络或下载链接！"
        return 1
    fi

    # 解压
    tar -xzvf "$GOST_DIR/$gost_pkg" -C "$GOST_DIR"
    if [ $? -ne 0 ]; then
        echo "解压失败！"
        rm -f "$GOST_DIR/$gost_pkg"
        return 1
    fi

    # 查找 gost 可执行文件并赋予权限
    gost_bin=$(find "$GOST_DIR" -type f -name 'gost*' | head -n 1)
    if [ -z "$gost_bin" ]; then
        echo "未找到 gost 可执行文件！"
        return 1
    fi
    chmod +x "$gost_bin"

    # # 清理压缩包
    rm -f "$GOST_DIR/$gost_pkg"

    echo "安装完成！Gost 路径: $GOST_DIR/gost"
}

# 卸载Gost
uninstall_gost() {
    echo "正在卸载Gost..."
    rm -rf $GOST_DIR
    echo "卸载完成！"
}

# 列出所有隧道服务
list_services() {
    services=($(systemctl list-unit-files --type=service --no-legend | grep '^gost_' | awk '{print $1}'))
    
    if [ ${#services[@]} -eq 0 ]; then
        echo "当前没有任何隧道服务"
        return 1
    fi

    echo "所有隧道服务列表："
    index=1
    for service in "${services[@]}"; do
        status=$(systemctl is-active "$service")
        if [ "$status" = "active" ]; then
            color=$GREEN
        else
            color=$RED
        fi
        echo -e "[$index] $service (状态: ${color}${status}${NC})"
        ((index++))
    done
}

# 创建新隧道
create_tunnel() {
    read -p "请输入隧道名称（xx部分）: " tunnel_name
    service_file="${SERVICE_DIR}/gost_${tunnel_name}.service"
    
    if [ -f "$service_file" ]; then
        echo "错误：该名称的服务已存在！"
        return
    fi

    read -p "请输入Gost命令（例如：-L=:8080）: " gost_cmd
    
    cat > $service_file <<EOF
[Unit]
Description = gost is a tunnel tool that's so simple that you say WOCAO
After = network.target

[Service]
Type=simple
ExecStart = $GOST_DIR/gost $gost_cmd
Restart = on-failure

[Install]
WantedBy = multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now gost_${tunnel_name}.service
    systemctl status gost_${tunnel_name}.service
}

# 删除隧道
delete_tunnel() {
    list_services || return

    read -p "请选择要删除的服务序号（可输入多个，用空格分隔，输入 all 删除全部）: " choices
    services=($(systemctl list-unit-files --type=service --no-legend | grep '^gost_' | awk '{print $1}'))

    if [ -z "$choices" ]; then
        echo "无效的选择！"
        return
    fi

    if [ "$choices" = "all" ]; then
        for service in "${services[@]}"; do
            echo "正在停止并删除服务: $service"
            systemctl stop "$service"
            systemctl disable "$service"
            rm -f "${SERVICE_DIR}/${service}"
        done
        systemctl daemon-reload
        echo "已完成全部服务的删除操作"
        return
    fi

    for choice in $choices; do
        if [ $choice -lt 1 ] || [ $choice -gt ${#services[@]} ]; then
            echo "序号 $choice 无效，跳过。"
            continue
        fi
        selected_service=${services[$((choice-1))]}
        echo "正在停止并删除服务: $selected_service"
        systemctl stop $selected_service
        systemctl disable $selected_service
        rm -f "${SERVICE_DIR}/${selected_service}"
    done
    systemctl daemon-reload
    echo "已完成所选服务的删除操作"
}

# 启动隧道
start_tunnel() {
    list_services || return
    read -p "请选择要启动的服务序号（可输入多个，用空格分隔，输入 all 启动全部）: " choices
    services=($(systemctl list-unit-files --type=service --no-legend | grep '^gost_' | awk '{print $1}'))

    if [ "$choices" = "all" ]; then
        for service in "${services[@]}"; do
            systemctl start "$service"
        done
        echo "所有隧道服务已启动"
        return
    fi

    if [ -z "$choices" ]; then
        echo "无效的选择！"
        return
    fi

    for choice in $choices; do
        if [ $choice -lt 1 ] || [ $choice -gt ${#services[@]} ]; then
            echo "序号 $choice 无效，跳过。"
            continue
        fi
        selected_service=${services[$((choice-1))]}
        systemctl start $selected_service
        echo "已启动服务: $selected_service"
    done
}

# 停止隧道
stop_tunnel() {
    list_services || return
    read -p "请选择要停止的服务序号（可输入多个，用空格分隔，输入 all 停止全部）: " choices
    services=($(systemctl list-unit-files --type=service --no-legend | grep '^gost_' | awk '{print $1}'))

    if [ "$choices" = "all" ]; then
        for service in "${services[@]}"; do
            systemctl stop "$service"
        done
        echo "所有隧道服务已停止"
        return
    fi

    if [ -z "$choices" ]; then
        echo "无效的选择！"
        return
    fi

    for choice in $choices; do
        if [ $choice -lt 1 ] || [ $choice -gt ${#services[@]} ]; then
            echo "序号 $choice 无效，跳过。"
            continue
        fi
        selected_service=${services[$((choice-1))]}
        systemctl stop $selected_service
        echo "已停止服务: $selected_service"
    done
}

# 重启隧道
restart_tunnel() {
    list_services || return
    read -p "请选择要重启的服务序号（可输入多个，用空格分隔，输入 all 重启全部）: " choices
    services=($(systemctl list-unit-files --type=service --no-legend | grep '^gost_' | awk '{print $1}'))

    if [ "$choices" = "all" ]; then
        for service in "${services[@]}"; do
            systemctl restart "$service"
        done
        echo "所有隧道服务已重启"
        return
    fi

    if [ -z "$choices" ]; then
        echo "无效的选择！"
        return
    fi

    for choice in $choices; do
        if [ $choice -lt 1 ] || [ $choice -gt ${#services[@]} ]; then
            echo "序号 $choice 无效，跳过。"
            continue
        fi
        selected_service=${services[$((choice-1))]}
        systemctl restart $selected_service
        echo "已重启服务: $selected_service"
    done
}

# 查看服务日志
view_tunnel_log() {
    list_services || return
    read -p "请选择要查看日志的服务序号: " choice
    services=($(systemctl list-unit-files --type=service --no-legend | grep '^gost_' | awk '{print $1}'))
    if [ -z "$choice" ] || [ $choice -lt 1 ] || [ $choice -gt ${#services[@]} ]; then
        echo "无效的选择！"
        return
    fi
    selected_service=${services[$((choice-1))]}
    journalctl -u $selected_service -e
}

# 备份所有隧道配置
backup_configs() {
    backup_dir="$GOST_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp ${SERVICE_DIR}/gost_*.service "$backup_dir" 2>/dev/null
    echo "已备份所有隧道配置到: $backup_dir"
}

# 还原隧道配置
restore_configs() {
    # 列出所有备份文件夹
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

    # 列出该文件夹下所有配置文件
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

# 编辑隧道配置
edit_tunnel_config() {
    list_services || return
    read -p "请选择要编辑的服务序号: " choice
    services=($(systemctl list-unit-files --type=service --no-legend | grep '^gost_' | awk '{print $1}'))
    if [ -z "$choice" ] || [ $choice -lt 1 ] || [ $choice -gt ${#services[@]} ]; then
        echo "无效的选择！"
        return
    fi
    selected_service=${services[$((choice-1))]}
    nano "${SERVICE_DIR}/${selected_service}"
    systemctl daemon-reload
    echo "已编辑并重载: $selected_service"
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo "============ Gost管理脚本 ============"
        check_install_status  # 新增状态显示
        list_services       # 列出所有隧道服务 
        echo "--------------------------------------"
        echo "1. 安装Gost"
        echo "2. 卸载Gost"
        echo "3. 创建新隧道"
        echo "4. 删除隧道"
        echo "5. 启动隧道"
        echo "6. 停止隧道"
        echo "7. 重启隧道"
        echo "8. 查看隧道日志"
        echo "9. 编辑隧道配置"
        echo "10. 备份所有隧道配置"
        echo "11. 还原隧道配置"

        echo "0. 退出"
        echo "======================================"
        
        read -p "请输入选择: " choice
        
        case $choice in
            1) install_gost ;;
            2) uninstall_gost ;;
            3) create_tunnel ;;
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
    done
}

# 脚本入口
check_root
main_menu