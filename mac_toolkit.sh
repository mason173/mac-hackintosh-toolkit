#!/bin/bash

# =============================================================================
# mac工具箱
# 作者: Mason
# 版本: 2.0.0
# 说明: 集成多种苹果相关功能的综合工具箱
#       • 制作macOS启动盘 (支持OpenCore引导)
#       • U盘格式化工具 (支持多种文件系统)
#       • 屏蔽/恢复macOS系统更新
#       • 适用于苹果系统维护和管理
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
ISO_FILE=""
MOUNT_POINT=""
INSTALLER_APP=""
FORMAT_TYPE=""
VOLUME_NAME=""
format_choice=""

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 打印标题
print_title() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "请不要以root用户身份运行此脚本！"
        exit 1
    fi
}

# 检查必要文件
check_files() {
    print_title "检查必要文件"
    
    # 检查ISO文件
    if [[ ! -f "Install-macOS-Catalina-10.15.7_19H15.iso" ]]; then
        print_error "未找到 Install-macOS-Catalina-10.15.7_19H15.iso 文件！"
        print_info "请确保ISO文件在当前目录下"
        exit 1
    fi
    print_success "找到macOS Catalina ISO文件"
    
    # 检查EFI文件夹
    if [[ ! -d "EFI" ]]; then
        print_error "未找到 EFI 文件夹！"
        print_info "请确保EFI文件夹在当前目录下"
        exit 1
    fi
    print_success "找到EFI文件夹"
    
    # 检查OpenCore配置文件
    if [[ ! -f "EFI/OC/config.plist" ]]; then
        print_error "未找到OpenCore配置文件: EFI/OC/config.plist"
        print_info "请确保config.plist文件在EFI/OC/目录下"
        exit 1
    fi
    print_success "找到OpenCore配置文件"
}

# 显示磁盘列表并让用户选择U盘
select_usb_disk() {
    print_title "选择U盘设备"
    
    print_info "当前系统中的磁盘设备："
    diskutil list
    
    echo
    print_warning "请仔细查看上面的磁盘列表，找到您的U盘设备"
    print_warning "注意：选择错误的磁盘将导致数据丢失！"
    echo
    
    while true; do
        read -p "请输入U盘的设备标识符 (例如: disk4): " USB_DISK
        
        # 验证输入格式
        if [[ ! $USB_DISK =~ ^disk[0-9]+$ ]]; then
            print_error "输入格式错误！请输入类似 disk4 的格式"
            continue
        fi
        
        # 检查设备是否存在
        if ! diskutil info "/dev/$USB_DISK" &>/dev/null; then
            print_error "设备 /dev/$USB_DISK 不存在！"
            continue
        fi
        
        # 显示设备信息并确认
        echo
        print_info "您选择的设备信息："
        diskutil info "/dev/$USB_DISK" | grep -E "Device Node|Media Name|Total Size"
        echo
        
        read -p "确认要使用此设备吗？这将删除设备上的所有数据！(y/N): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            break
        fi
    done
    
    USB_DEVICE="/dev/$USB_DISK"
    print_success "已选择设备: $USB_DEVICE"
}



# 选择格式化类型
select_format_type() {
    print_title "选择格式化类型"
    
    echo "请选择U盘格式化类型："
    echo
    echo "1) Mac OS Extended (Journaled) - HFS+"
    echo "   • 适用于：macOS启动盘制作"
    echo "   • 优点：完全兼容macOS，支持日志记录"
    echo "   • 缺点：Windows系统无法直接读写"
    echo
    echo "2) ExFAT"
    echo "   • 适用于：跨平台文件存储"
    echo "   • 优点：Windows/macOS/Linux都支持，支持大文件"
    echo "   • 缺点：不能用于制作macOS启动盘"
    echo
    echo "3) FAT32"
    echo "   • 适用于：老设备兼容性"
    echo "   • 优点：几乎所有设备都支持"
    echo "   • 缺点：单文件最大4GB，不能用于制作macOS启动盘"
    echo
    echo "4) APFS"
    echo "   • 适用于：现代macOS系统"
    echo "   • 优点：Apple最新文件系统，性能优秀"
    echo "   • 缺点：只有macOS 10.13+支持，不能用于启动盘制作"
    echo
    
    while true; do
        read -p "请输入选择 (1-4): " format_choice
        case $format_choice in
            1)
                FORMAT_TYPE="Mac OS Extended (Journaled)"
                VOLUME_NAME="INSTALLER"
                print_success "已选择 Mac OS Extended (Journaled) 格式"
                break
                ;;
            2)
                FORMAT_TYPE="ExFAT"
                VOLUME_NAME="USB_DRIVE"
                print_success "已选择 ExFAT 格式"
                break
                ;;
            3)
                FORMAT_TYPE="MS-DOS FAT32"
                VOLUME_NAME="USB_DRIVE"
                print_success "已选择 FAT32 格式"
                break
                ;;
            4)
                FORMAT_TYPE="APFS"
                VOLUME_NAME="USB_DRIVE"
                print_success "已选择 APFS 格式"
                break
                ;;
            *)
                print_error "无效选择，请输入 1-4"
                ;;
        esac
    done
    
    echo
}

# 格式化U盘
format_usb() {
    print_title "格式化U盘"
    
    print_warning "即将格式化U盘，所有数据将被删除！"
    print_info "格式化类型: $FORMAT_TYPE"
    print_info "卷标名称: $VOLUME_NAME"
    echo
    read -p "确认继续？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        exit 0
    fi
    
    print_info "正在格式化U盘为 $FORMAT_TYPE..."
    if sudo diskutil partitionDisk "$USB_DEVICE" GPT "$FORMAT_TYPE" "$VOLUME_NAME" 100%; then
        print_success "U盘格式化完成"
        print_info "格式: $FORMAT_TYPE"
        print_info "卷标: $VOLUME_NAME"
        # 等待格式化完成
        sleep 3
    else
        print_error "U盘格式化失败！"
        exit 1
    fi
    
    echo
}

# 独立的格式化功能
format_usb_only() {
    clear
    echo -e "${BLUE}"
    echo "=============================================================================="
    echo "                           U盘格式化工具"
    echo "=============================================================================="
    echo -e "${NC}"
    echo
    print_warning "⚠️  重要提醒：此功能将完全格式化您选择的U盘，请确保已备份重要数据！"
    echo
    read -p "按回车键继续，或按Ctrl+C取消..."
    echo
    
    select_usb_disk
    select_format_type
    format_usb
    
    print_success "🎉 U盘格式化完成！"
    echo
    print_info "📋 格式化信息："
    echo "   • 设备: $USB_DEVICE"
    echo "   • 格式: $FORMAT_TYPE"
    echo "   • 卷标: $VOLUME_NAME"
    echo
    
    # 显示使用建议
    case $format_choice in
        1)
            print_info "💡 使用建议："
            echo "   • 此格式适合制作macOS启动盘"
            echo "   • 可以继续使用本脚本制作启动盘"
            ;;
        2)
            print_info "💡 使用建议："
            echo "   • 此格式适合在Windows和macOS之间传输文件"
            echo "   • 支持大于4GB的单个文件"
            ;;
        3)
            print_info "💡 使用建议："
            echo "   • 此格式兼容性最好，几乎所有设备都支持"
            echo "   • 单个文件不能超过4GB"
            ;;
        4)
            print_info "💡 使用建议："
            echo "   • 此格式性能最佳，但只有较新的macOS支持"
            echo "   • 适合作为macOS的外部存储设备"
            ;;
    esac
}

# 挂载ISO镜像
mount_iso() {
    print_title "挂载ISO镜像"
    
    print_info "正在挂载macOS Catalina ISO镜像..."
    if hdiutil mount "Install-macOS-Catalina-10.15.7_19H15.iso"; then
        print_success "ISO镜像挂载完成"
        # 等待挂载完成
        sleep 2
    else
        print_error "ISO镜像挂载失败！"
        exit 1
    fi
}

# 创建启动U盘
create_installer() {
    print_title "创建macOS安装U盘"
    
    print_info "正在使用createinstallmedia创建启动U盘..."
    print_warning "此过程可能需要20-30分钟，请耐心等待"
    
    if sudo "/Volumes/Install macOS Catalina/Install macOS Catalina.app/Contents/Resources/createinstallmedia" --volume /Volumes/INSTALLER; then
        print_success "macOS安装U盘创建完成"
    else
        print_error "创建安装U盘失败！"
        exit 1
    fi
}

# 挂载EFI分区
mount_efi() {
    print_title "挂载EFI分区"
    
    print_info "正在挂载U盘的EFI分区..."
    if sudo diskutil mount "${USB_DEVICE}s1"; then
        print_success "EFI分区挂载完成"
    else
        print_error "EFI分区挂载失败！"
        exit 1
    fi
}

# 复制OpenCore文件
copy_opencore() {
    print_title "复制OpenCore引导文件"
    
    print_info "正在复制OpenCore EFI文件到U盘..."
    if cp -R "EFI" "/Volumes/EFI/"; then
        print_success "OpenCore文件复制完成"
    else
        print_error "OpenCore文件复制失败！"
        exit 1
    fi
    
    # 验证配置文件
    print_info "正在验证OpenCore配置..."
    if [[ -f "/Volumes/EFI/EFI/OC/config.plist" ]]; then
        print_success "OpenCore配置文件已就绪"
    else
        print_error "OpenCore配置文件缺失！"
        exit 1
    fi
}

# 清理工作
cleanup() {
    print_title "清理工作"
    
    print_info "正在卸载EFI分区..."
    sudo diskutil unmount "/Volumes/EFI" 2>/dev/null
    
    print_info "正在卸载ISO镜像..."
    hdiutil unmount "/Volumes/Install macOS Catalina" 2>/dev/null
    
    print_success "清理工作完成"
}

# 显示完成信息
show_completion() {
    print_title "制作完成"
    
    print_success "🎉 带有OpenCore引导的macOS Catalina启动U盘制作完成！"
    echo
    print_info "使用说明："
    echo "1. 将U盘插入目标电脑"
    echo "2. 开机时按住Option键(⌥)选择启动设备"
    echo "3. 在OpenCore引导菜单中选择'Install macOS Catalina'"
    echo "4. 按照屏幕提示完成macOS安装"
    echo
    print_warning "注意事项："
    echo "• 确保目标电脑硬件与OpenCore配置兼容"
    echo "• 安装前请备份重要数据"
    echo "• 如遇启动问题，可能需要调整OpenCore配置"
    echo
    print_info "配置文件说明："
    echo "• 使用您预配置的 config.plist 文件"
    echo "• 如需更换配置，可重新挂载EFI分区进行修改"
}

# 屏蔽macOS更新功能
block_macos_updates() {
    print_title "屏蔽macOS系统更新"
    
    print_info "此功能将通过以下方式屏蔽macOS系统更新："
    echo "1. 禁用软件更新守护进程"
    echo "2. 阻止系统更新检查"
    echo "3. 修改系统更新配置"
    echo
    
    print_warning "⚠️  注意事项："
    echo "• 此操作需要管理员权限"
    echo "• 屏蔽更新可能影响系统安全性"
    echo "• 建议定期手动检查重要安全更新"
    echo "• 可随时恢复系统更新功能"
    echo
    
    read -p "确认要屏蔽macOS系统更新吗？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return
    fi
    
    print_info "正在屏蔽macOS系统更新..."
    
    # 禁用软件更新守护进程
    print_info "禁用软件更新守护进程..."
    sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.softwareupdated.plist 2>/dev/null || true
    
    # 禁用自动更新检查
    print_info "禁用自动更新检查..."
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool false
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool false
    
    # 用户级别设置
    defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false
    defaults write com.apple.SoftwareUpdate AutomaticDownload -bool false
    defaults write com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
    
    # 屏蔽更新服务器（可选）
    print_info "添加更新服务器屏蔽规则..."
    if ! grep -q "swscan.apple.com" /etc/hosts; then
        echo "127.0.0.1 swscan.apple.com" | sudo tee -a /etc/hosts > /dev/null
        echo "127.0.0.1 swquery.apple.com" | sudo tee -a /etc/hosts > /dev/null
        echo "127.0.0.1 swdownload.apple.com" | sudo tee -a /etc/hosts > /dev/null
        echo "127.0.0.1 swcdn.apple.com" | sudo tee -a /etc/hosts > /dev/null
    fi
    
    print_success "✅ macOS系统更新已成功屏蔽！"
    echo
    print_info "验证结果："
    echo "• 软件更新守护进程已禁用"
    echo "• 自动更新检查已关闭"
    echo "• 更新服务器已屏蔽"
    echo
    print_warning "如需恢复系统更新，请使用恢复功能"
}

# 恢复macOS更新功能
restore_macos_updates() {
    print_title "恢复macOS系统更新"
    
    print_info "此功能将恢复macOS系统更新功能"
    echo
    
    read -p "确认要恢复macOS系统更新吗？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return
    fi
    
    print_info "正在恢复macOS系统更新..."
    
    # 启用软件更新守护进程
    print_info "启用软件更新守护进程..."
    sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.softwareupdated.plist 2>/dev/null || true
    
    # 恢复自动更新设置
    print_info "恢复自动更新设置..."
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
    
    # 用户级别设置
    defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
    defaults write com.apple.SoftwareUpdate AutomaticDownload -bool true
    
    # 移除hosts文件中的屏蔽规则
    print_info "移除更新服务器屏蔽规则..."
    sudo sed -i '' '/swscan.apple.com/d' /etc/hosts
    sudo sed -i '' '/swquery.apple.com/d' /etc/hosts
    sudo sed -i '' '/swdownload.apple.com/d' /etc/hosts
    sudo sed -i '' '/swcdn.apple.com/d' /etc/hosts
    
    print_success "✅ macOS系统更新功能已恢复！"
    echo
    print_info "建议重启系统以确保所有设置生效"
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${BLUE}"
    echo "=============================================================================="
    echo "                        macOS 黑苹果工具箱 v2.0"
    echo "                      Hackintosh Toolkit for macOS"
    echo "=============================================================================="
    echo -e "${NC}"
    echo
    echo "请选择要执行的操作："
    echo
    echo "1) 制作macOS启动盘"
    echo "   • 自动检测ISO文件并制作带OpenCore引导的启动盘"
    echo "   • 需要准备：macOS ISO文件 + EFI文件夹"
    echo
    echo "2) 格式化U盘"
    echo "   • 支持多种格式：HFS+、ExFAT、FAT32、APFS"
    echo "   • 可选择适合不同用途的文件系统"
    echo
    echo "3) 屏蔽macOS系统更新"
    echo "   • 阻止系统自动检查和下载更新"
    echo "   • 适用于黑苹果系统稳定性维护"
    echo
    echo "4) 恢复macOS系统更新"
    echo "   • 恢复系统更新功能"
    echo "   • 重新启用自动更新检查"
    echo
    echo "5) 退出程序"
    echo
}

# 制作启动盘的主函数
make_bootable_usb() {
    clear
    echo -e "${BLUE}"
    echo "=============================================================================="
    echo "                    macOS 启动盘制作工具 (OpenCore 引导)"
    echo "=============================================================================="
    echo -e "${NC}"
    echo
    print_warning "⚠️  重要提醒：此脚本将完全格式化您选择的U盘，请确保已备份重要数据！"
    echo
    read -p "按回车键继续，或按Ctrl+C取消..."
    
    # 执行各个步骤
    check_root
    check_files
    select_usb_disk
    
    # 对于启动盘制作，强制使用HFS+格式
    FORMAT_TYPE="Mac OS Extended (Journaled)"
    VOLUME_NAME="INSTALLER"
    format_choice=1
    
    echo
    print_warning "最后确认："
    echo "• 目标设备: $USB_DEVICE"
    echo "• ISO文件: $ISO_FILE"
    echo "• 格式化类型: $FORMAT_TYPE"
    echo "• 所有数据将被删除！"
    echo
    read -p "确认开始制作启动盘？(y/N): " final_confirm
    if [[ ! "$final_confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return
    fi
    
    format_usb
    mount_iso
    create_installer
    mount_efi
    copy_opencore
    cleanup
    show_completion
}

# 主函数
main() {
    while true; do
        show_main_menu
        
        read -p "请输入选择 (1-5): " menu_choice
        case $menu_choice in
            1)
                make_bootable_usb
                echo
                read -p "按回车键返回主菜单..."
                ;;
            2)
                format_usb_only
                echo
                read -p "按回车键返回主菜单..."
                ;;
            3)
                block_macos_updates
                echo
                read -p "按回车键返回主菜单..."
                ;;
            4)
                restore_macos_updates
                echo
                read -p "按回车键返回主菜单..."
                ;;
            5)
                print_info "感谢使用！"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 1-5"
                sleep 2
                ;;
        esac
    done
}

# 错误处理
trap 'print_error "脚本执行过程中发生错误，正在清理..."; cleanup; exit 1' ERR

# 运行主函数
main "$@"
