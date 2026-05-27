#!/bin/bash
# Make by lurenjbd 2025-02-10
# Version 2.1
# Edited 2025-08-26
# Patch to make PCT support OCI.

########### Variable ###########

MIN_VERSION="9.1.1"
RESTORE_MODE=0
SKIP_CONFIRM=0
DEL_BACKUP=0
LANGUAGE="zh_cn"

# Color code
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

########### Function ###########
show_usage() {
	echo -e "${BLUE}==========================================================${NC}"
	echo -e "${BLUE}                 PVE OCI Support Patch Tool${NC}"
	echo -e "${BLUE}==========================================================${NC}"
	echo -e "用法 (Usage): $0 [选项 (Options)]"
	echo ""
	echo -e "选项 (Options):"
	echo -e "  -h, --help       显示此帮助信息 (Show this help message)"
	echo -e "  -R, --restore    恢复原始文件 (Restore original files)"
	echo -e "  -D, --del-backup 恢复后删除备份文件 (Delete backup files after restore)"
	echo -e "  -y, --yes        跳过确认提示 (Skip confirmation prompts)"
	echo -e "  -c, --chinese    使用中文显示消息（默认）"
	echo -e "  -e, --english    Use English for messages"
	echo ""
	echo -e "${BLUE}==========================================================${NC}"
}

printf_msg() {
	local text_zh="$1"
	local text_en="$2"
	local type="${3:-INFO}"

	local color=$BLUE
	case "$type" in
		SUCCESS) color=$GREEN ;;
		WARNING) color=$YELLOW ;;
		ERROR) color=$RED ;;
		*) color=$BLUE ;;
	esac

	if [[ "$LANGUAGE" == "zh_cn" ]]; then
		echo -e "${color}${text_zh}${NC}"
	else
		echo -e "${color}${text_en}${NC}"
	fi
}

parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-h|--help)
				show_usage
				exit 0
				;;
			-R|--restore)
				RESTORE_MODE=1
				shift
				;;
			-D|--del-backup)
				DEL_BACKUP=1
				shift
				;;
			-y|--yes)
				SKIP_CONFIRM=1
				shift
				;;
			-c|--chinese)
				LANGUAGE="zh_cn"
				shift
				;;
			-e|--english)
				LANGUAGE="en_us"
				shift
				;;
			*)
				printf_msg "错误: 未知选项 $1" \
					"Error: Unknown option $1" \
					"ERROR"
				show_usage
				exit 1
				;;
		esac
	done
}

generate_path() {
	CREATE_NEW_FILE=0

	local FIRST_LINE_PATH=$(awk 'NR==1 {print $2}' "$1")
	local SECOND_LINE_PATH=$(awk 'NR==2 {print $2}' "$1")

	if [[ "$FIRST_LINE_PATH" == "/dev/null" ]]; then
		CREATE_NEW_FILE=1
	fi

	if [[ ! "${SECOND_LINE_PATH}" =~ ^/ ]]; then
		printf_msg "无法从补丁中获取目标文件路径: $1" \
			"Cannot get target file path from patch: $1" \
			"ERROR"
		TARGET_FILE=''
		return 1
	fi

	TARGET_FILE="${SECOND_LINE_PATH}"
	return 0
}

check_ready() {
	generate_path "$1" || return 1

	BACKUP_FILE="$TARGET_FILE.bak-${BACKUP_FILE_SUFFIX}"

	if [ -e "$BACKUP_FILE" ]; then
		printf_msg "备份文件已存在: $BACKUP_FILE" \
			"Backup file already exists: $BACKUP_FILE" \
			"WARNING"
	elif [ -e "$TARGET_FILE" ]; then
		NEED_BACKUP_FILES+=("$TARGET_FILE")
	else
		if [[ "$CREATE_NEW_FILE" -eq 0 ]]; then
			printf_msg "未找到目标文件: $TARGET_FILE" \
				"Target file not found: $TARGET_FILE" \
				"WARNING"
		fi
	fi

	TARGET_DIR=$(dirname "$TARGET_FILE")

	if [[ ! -d "$TARGET_DIR" && "$CREATE_NEW_FILE" -eq 1 ]]; then
		printf_msg "目标目录不存在，将创建: $TARGET_DIR" \
			"Target directory does not exist, will create: $TARGET_DIR" \
			"INFO"
		mkdir -p "$TARGET_DIR"
	fi

	PATCH_FILE="$1"
	if ! patch --dry-run -d "$TARGET_DIR" < "$PATCH_FILE" >/dev/null 2>&1; then
		printf_msg "补丁 $(basename ${PATCH_FILE}) 无法应用。请检查补丁文件和目标目录。" \
			"$(basename ${PATCH_FILE}) Patch cannot be apply. Please check the patch file and target directory." \
			"ERROR"
		patch --dry-run -d "$TARGET_DIR" < "$PATCH_FILE"
		return 1
	else
		if [[ "$CREATE_NEW_FILE" -eq 1 ]]; then
			printf_msg "将创建新文件: $TARGET_FILE" \
				"Will create new file: $TARGET_FILE" \
				"SUCCESS"
		else
			printf_msg "补丁 $(basename ${PATCH_FILE}) 可以成功应用" \
				"$(basename ${PATCH_FILE}) Patch can be apply successfully." \
				"SUCCESS"
		fi
		CHECK_PATCH_PASS+=("$1")
		return 0
	fi

	return 1
}

restore_patch(){
	generate_path "$1" || return 1

	BACKUP_FILE="$TARGET_FILE.bak-${BACKUP_FILE_SUFFIX}"

	if [[ "$CREATE_NEW_FILE" -eq 1 ]]; then
		if [ -e "$TARGET_FILE" ]; then
			rm -f "$TARGET_FILE"
			printf_msg "已删除新创建的文件 $TARGET_FILE" \
				"Deleted newly created file $TARGET_FILE" \
				"INFO"
		else
			printf_msg "文件不存在，无需删除: $TARGET_FILE" \
				"File does not exist, no need to delete: $TARGET_FILE" \
				"INFO"
		fi
	else
		TARGET_DIR=$(dirname "$TARGET_FILE")
		PATCH_FILE="$1"

		printf_msg "尝试反向应用补丁: $PATCH_FILE" \
			"Trying to reverse apply patch: $PATCH_FILE" \
			"INFO"

		if [ -e "$TARGET_FILE" ] && patch -R --dry-run -d "$TARGET_DIR" < "$PATCH_FILE" >/dev/null 2>&1; then
			patch -R -d "$TARGET_DIR" < "$PATCH_FILE" > /dev/null 2>&1
			printf_msg "成功反向应用补丁，恢复文件 $TARGET_FILE" \
				"Successfully reverse applied patch to restore $TARGET_FILE" \
				"SUCCESS"
			if [ -f "$TARGET_FILE.orig" ]; then
				printf_msg "清理 $TARGET_FILE.orig 文件" \
					"Cleaning up $TARGET_FILE.orig files" \
					"INFO"
				rm "$TARGET_FILE.orig"
			fi
			if [ "$DEL_BACKUP" -eq 1 ] && [ -e "$BACKUP_FILE" ]; then
				rm -f $BACKUP_FILE
				printf_msg "已删除备份文件 $BACKUP_FILE" \
					"Deleted backup file $BACKUP_FILE" \
					"SUCCESS"
			fi
		elif [ -e "$BACKUP_FILE" ]; then
			printf_msg "反向应用补丁失败，使用备份文件恢复" \
				"Reverse patch failed, using backup file to restore" \
				"WARNING"
			mv $BACKUP_FILE $TARGET_FILE
			printf_msg "成功恢复文件 $TARGET_FILE" \
				"Restore $TARGET_FILE file successfully." \
				"SUCCESS"
		else
			printf_msg "未找到备份文件 $BACKUP_FILE 且无法反向应用补丁" \
				"Backup file $BACKUP_FILE not found and cannot reverse apply patch." \
				"WARNING"
		fi
	fi

	return 0
}

arrays_equal() {
	local arr1=("${!1}")
	local arr2=("${!2}")

	[[ ${#arr1[@]} -ne ${#arr2[@]} ]] && return 1

	local sorted1=$(printf '%s\n' "${arr1[@]}" | sort)
	local sorted2=$(printf '%s\n' "${arr2[@]}" | sort)

	diff -u <(printf '%s\n' "$sorted1") <(printf '%s\n' "$sorted2") >/dev/null && return 0

	return 1
}

version_ge() {
	local v1="$1"
	local v2="$2"
	[[ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" == "$v2" ]]
}

load_module() {
	local module=$1
	local params=$2
	local modules_file="/etc/modules"
	local modprobe_conf_file="/etc/modprobe.d/$module.conf"

	if ! modinfo "$module" &>/dev/null; then
		printf_msg "$module 模块不存在于内核中" \
			"$module module does not exist in the kernel" \
			"ERROR"
		return 1
	fi

	if ! lsmod | grep -q "$module"; then
		printf_msg "$module 模块未加载，正在加载..." \
			"$module is not loaded, loading module..." \
			"INFO"
		if [[ -n "$params" ]]; then
			modprobe "$module" $params
		else
			modprobe "$module"
		fi
	else
		printf_msg "$module 模块已加载" \
			"$module is already loaded." \
			"INFO"
	fi

	if ! grep -q "$module" "$modules_file"; then
		printf_msg "添加 $module 到 $modules_file" \
			"Adding $module to $modules_file" \
			"INFO"
		sed -i -e '$a\' "$modules_file"
		echo "$module" >> "$modules_file"
	fi
	if [[ -n "$params" && ! -f "$modprobe_conf_file" ]]; then
		echo "options $module $params" > "$modprobe_conf_file"
	fi
}

check_running_vms() {
	local running_vms=0
	local running_cts=0

	if command -v qm &> /dev/null; then
		running_vms=$(qm list | grep running | wc -l)
	fi

	if command -v pct &> /dev/null; then
		running_cts=$(pct list | grep running | wc -l)
	fi

	total=$((running_vms + running_cts))
	echo "$total"
}

cleanup() {
	if [ "$Need_RestartAPI" -eq 1 ]; then
		printf_msg "正在重启PVE Web界面服务..." \
			"Restarting PVE Web UI services..." \
			"INFO"
		systemctl restart pve{proxy,daemon,statd}.service
	fi
}
trap cleanup EXIT

read_user_input() {
	local prompt_zh="$1"
	local prompt_en="$2"
	local result

	if [[ "$LANGUAGE" == "zh_cn" ]]; then
		read -p "$prompt_zh" result
	else
		read -p "$prompt_en" result
	fi

	echo "$result"
}

########### Main ###########

PATCH_FILE_LIST=()
CHECK_PATCH_PASS=()
NEED_BACKUP_FILES=()
Need_RestartAPI=0

parse_arguments "$@"

if [ "$(uname -m)" != "x86_64" ]; then
	printf_msg "当前系统架构为 $(uname -m)，此脚本仅支持 x86_64 架构。" \
		"Current system architecture is $(uname -m). This script only supports x86_64." \
		"ERROR"
	exit 1
fi

if ! command -v pveversion &>/dev/null; then
	printf_msg "未检测到 pveversion 命令，请确认是否运行在 PVE 环境中。" \
		"pveversion command not found. Please ensure you are running in a PVE environment." \
		"ERROR"
	exit 1
fi

PVE_VERSION=$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}' 2>/dev/null)

if [[ "$(echo -e "$MIN_VERSION\n$PVE_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]]; then
	printf_msg "当前PVE版本 $PVE_VERSION 低于 $MIN_VERSION。请升级PVE系统版本。" \
		"Current PVE version $PVE_VERSION is lower than $MIN_VERSION. Please upgrade the PVE system version." \
		"WARNING"
	exit 1
fi

if [[ "$SKIP_CONFIRM" -ne 1 ]]; then
	printf_msg "我已了解该脚本的作用，并自愿承担对应的风险。" \
		"I have understood the purpose of this script and voluntarily assume the corresponding risks." \
		"INFO"
	user_input=$(read_user_input "请输入 y/Y 继续执行: " "Please enter y/Y to continue: ")
	case "$user_input" in
		y|Y) Need_RestartAPI=1;;
		*)
			printf_msg "输入无效或用户取消操作，脚本退出。" \
				"Invalid input or operation canceled, exiting the script." \
				"ERROR"
			exit 1
			;;
	esac
else
	Need_RestartAPI=1
fi

if [ -f /usr/share/perl5/PVE/LXC/Setup/Oci.pm ] && [ "$RESTORE_MODE" -eq 0 ]; then
	printf_msg "该补丁已执行，请不要再次执行。如需恢复，请使用 -R 或 --restore 参数。" \
		"The patch has already been applied. Please do not apply it again. If you need to revert, use the -R or --restore option." \
		"WARNING"
	Need_RestartAPI=0
	exit 0
fi

if ! command -v patch &> /dev/null; then
	printf_msg "未找到 patch 命令，正在安装..." \
		"The patch command is not found. Installing it now..." \
		"INFO"
	apt update
	if [[ $? -ne 0 ]]; then
		printf_msg "更新软件源失败，请检查网络" \
			"Failed to update package list. Please check your network." \
			"ERROR"
		exit 1
	fi
	apt install -y patch
	if [[ $? -eq 0 ]]; then
		clear
		printf_msg "patch 命令安装成功" \
			"patch command was installed successfully." \
			"SUCCESS"
	else
		printf_msg "patch 命令安装失败，请手动安装" \
			"patch command installation failed. Please install it manually." \
			"ERROR"
		exit 1
	fi
fi

# Determine the patch directory based on PVE version
FIX_VERSION=$(echo $PVE_VERSION |  awk -F'.' '{print $1"."$2".x"}' )

BACKUP_FILE_SUFFIX=$(echo $PVE_VERSION |  awk -F'.' '{print $1""$2""$3""}')
PATCH_TMP_DIR=$(find -L ./pct-oci-patch/${FIX_VERSION} -name "*.diff" 2>/dev/null)

if [[ -z "$PATCH_TMP_DIR" ]]; then
	printf_msg "未找到适用于PVE版本 ${PVE_VERSION} 的补丁文件。" \
		"No patch files found for PVE version ${PVE_VERSION}." \
		"WARNING"
	Need_RestartAPI=0
	exit 1
fi

if [[ "$RESTORE_MODE" -eq 1 ]]; then
	if [ ! -f /usr/share/perl5/PVE/LXC/Setup/Oci.pm ]; then
		printf_msg "未检测到补丁应用的痕迹，无需恢复。" \
			"No patch application detected, no need to restore." \
			"WARNING"
		Need_RestartAPI=0
		exit 0
	fi

	for FILE in $PATCH_TMP_DIR; do
		restore_patch "$FILE"
	done

	modules=("binder_linux" "mac80211_hwsim")
	for module in "${modules[@]}"; do
		if grep -q "$module" /etc/modules; then
		printf_msg "从 /etc/modules 中移除 $module" \
			"Removing $module from /etc/modules" \
			"INFO"
		sed -i "/^$module$/d" /etc/modules
		fi
	done
	rm /etc/modprobe.d/binder_linux.conf

	printf_msg "恢复完成，已还原到原始状态" \
		"Restoration completed, system has been reverted to original state" \
		"SUCCESS"
	exit 0
fi

for FILE in $PATCH_TMP_DIR; do
	check_ready "$FILE"
	PATCH_FILE_LIST+=("$FILE")
done

if ! arrays_equal PATCH_FILE_LIST[@] CHECK_PATCH_PASS[@]; then
	printf_msg "补丁检查不通过，脚本可能不支持 ${PVE_VERSION} 版本" \
		"Patch check failed, script may not support ${PVE_VERSION} version" \
		"ERROR"
	Need_RestartAPI=0
	exit 0
else
	printf_msg "补丁检查通过！可以应用到 ${PVE_VERSION} 版本" \
		"Patch check passed! Can be applied to ${PVE_VERSION} version" \
		"SUCCESS"
fi

for FILE in "${NEED_BACKUP_FILES[@]}"; do
	BACKUP_FILE="$FILE.bak-${BACKUP_FILE_SUFFIX}"
	printf_msg "备份 $FILE 到 $BACKUP_FILE" \
		"Backing up $FILE to $BACKUP_FILE" \
		"INFO"
	cp "$FILE" "$BACKUP_FILE"
done

for FILE in "${CHECK_PATCH_PASS[@]}"; do
	printf_msg "应用补丁: $FILE" \
		"Applying patch: $FILE" \
		"INFO"
	generate_path $FILE
	TARGET_DIR=$(dirname "$TARGET_FILE")
	PATCH_FILE="$FILE"
	patch -d "$TARGET_DIR" < "$PATCH_FILE" > /dev/null 2>&1
	if [ -f "$TARGET_FILE.orig" ]; then
		printf_msg "清理 $TARGET_FILE.orig 文件" \
			"Cleaning up $TARGET_FILE.orig files" \
			"INFO"
		rm "$TARGET_FILE.orig"
	fi
done

load_module "binder_linux" "devices=binder,hwbinder,vndbinder"
load_module "mac80211_hwsim"

printf_msg "所有操作已完成！" \
	"All operations completed successfully!" \
	"SUCCESS"
printf_msg "作者: toss-a lurenjbd" \
	"Author: lurenjbd" \
	"INFO"

RUNNING_VMS=$(check_running_vms)
if [ -n "$RUNNING_VMS" ] && [ "$RUNNING_VMS" -gt 0 ]; then
	printf_msg "检测到当前有 $RUNNING_VMS 个运行中的虚拟机或容器，建议重启PVE宿主机以确保补丁完全生效。" \
		"Detected $RUNNING_VMS running VMs or containers, it is recommended to restart the PVE host to ensure the patch takes full effect." \
		"WARNING"
fi
