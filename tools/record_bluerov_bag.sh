#!/usr/bin/env bash
# -*- coding: utf-8 -*-

###############################################################################
# BlueROV rosbag 一键录制脚本
#
# 功能：
#   根据文件内部配置，选择是否录制：
#   IMU、深度计、相机、RC、电池、声呐、TF 等数据。
#
# 用户日常只需要运行：
#   ./tools/record_bluerov_bag.sh
#
# 所有选择都在“用户配置区”修改，命令行启动时不需要额外输入参数。
###############################################################################

############################
# 1. 用户配置区
############################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# 保存路径
BAG_DIR="${BLUEROV_BAG_DIR:-$HOME/bluerov_bag}"

# 文件名前缀
BAG_PREFIX="bluerov_all_sensors"

# 是否自动加时间戳
USE_TIMESTAMP=1

# 是否使用 bz2 压缩
# 注意：压缩会减小文件，但会增加 CPU 占用。
USE_BZ2=0

# 是否录制各类数据
RECORD_IMU=1
RECORD_IMU_DISPLAY=1
RECORD_DEPTH=1
RECORD_CAMERA=1
RECORD_RC=1
RECORD_BATTERY=1
RECORD_TF=1
RECORD_SONAR=0

# 相机录制选项
# 长时间实验建议录 compressed，不建议录 raw。
RECORD_CAMERA_COMPRESSED=1
RECORD_CAMERA_RAW=0

# 声呐录制选项
# 原始矩形图：保留 SDK 原始输出，后期算法更建议保留。
# 扇形图：用于展示和人工观察。
RECORD_SONAR_RAW_IMAGE=1
RECORD_SONAR_FAN_IMAGE=1

# 如果系统存在 compressed 话题，可以录 compressed，文件更小。
# 若你发现 compressed 话题不存在，设为 0。
RECORD_SONAR_COMPRESSED=0

RECORD_SONAR_RANGE=1
RECORD_SONAR_STATUS=1
RECORD_SONAR_CONTROL=1

# 预留：如果以后你把声呐转换成 LaserScan 或 PointCloud2，可以开启。
RECORD_SONAR_SCAN=0
RECORD_SONAR_POINTS=0

############################
# 2. 内部函数区
############################

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
NC="\033[0m"

info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

ok() {
    echo -e "${GREEN}[ OK ] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

fail() {
    echo -e "${RED}[FAIL] $1${NC}"
}

source_ros_env() {
    if [ -f "/opt/ros/noetic/setup.bash" ]; then
        source /opt/ros/noetic/setup.bash
    else
        fail "未找到 /opt/ros/noetic/setup.bash。"
        exit 1
    fi

    if [ -f "$WS_DIR/devel/setup.bash" ]; then
        source "$WS_DIR/devel/setup.bash"
    else
        warn "未找到 $WS_DIR/devel/setup.bash，只使用系统 ROS 环境。"
    fi
}

check_roscore() {
    if rosnode list >/dev/null 2>&1; then
        ok "检测到 roscore 正在运行。"
    else
        fail "未检测到 roscore。请先运行 start_bluerov_sensors.sh。"
        exit 1
    fi
}

topic_exists() {
    rostopic list 2>/dev/null | grep -Fxq "$1"
}

add_topic() {
    local topic="$1"
    local desc="$2"

    TOPICS+=("$topic")

    if topic_exists "$topic"; then
        ok "录制话题存在：$topic  ← $desc"
    else
        warn "当前未检测到话题：$topic  ← $desc"
        warn "rosbag 仍会等待该话题，若后续出现也会录制。"
    fi
}

############################
# 3. 主流程
############################

echo "============================================================"
echo " BlueROV rosbag 一键录制"
echo "============================================================"

source_ros_env
check_roscore

mkdir -p "$BAG_DIR"

if [ "$USE_TIMESTAMP" -eq 1 ]; then
    TIME_STR=$(date +"%Y%m%d_%H%M%S")
    BAG_NAME="${BAG_PREFIX}_${TIME_STR}.bag"
else
    BAG_NAME="${BAG_PREFIX}.bag"
fi

BAG_PATH="$BAG_DIR/$BAG_NAME"

TOPICS=()

if [ "$RECORD_IMU" -eq 1 ]; then
    add_topic "/mavros/state" "飞控连接状态、模式、解锁状态"
    add_topic "/mavros/imu/data" "融合 IMU 数据"
    add_topic "/mavros/imu/data_raw" "原始 IMU 数据"
    add_topic "/mavros/imu/mag" "磁力计数据"
fi

if [ "$RECORD_IMU_DISPLAY" -eq 1 ]; then
    add_topic "/bluerov/imu/linear_acceleration" "整理后的 xyz 加速度"
    add_topic "/bluerov/imu/angular_velocity" "整理后的 xyz 角速度"
    add_topic "/bluerov/imu/text_marker" "RViz IMU 数值显示"
    add_topic "/bluerov/imu/vector_markers" "RViz IMU 箭头显示"
fi

if [ "$RECORD_DEPTH" -eq 1 ]; then
    add_topic "/mavros/imu/static_pressure" "深度计原始压力数据"
    add_topic "/mavros/imu/temperature_baro" "压力计温度"
    add_topic "/bluerov/depth_m" "换算后的深度，单位 m"
    add_topic "/bluerov/depth_marker" "RViz 深度显示 Marker"
fi

if [ "$RECORD_CAMERA" -eq 1 ]; then
    if [ "$RECORD_CAMERA_COMPRESSED" -eq 1 ]; then
        add_topic "/bluerov/camera/image_raw/compressed" "压缩相机图像，推荐长期录制"
    fi

    if [ "$RECORD_CAMERA_RAW" -eq 1 ]; then
        add_topic "/bluerov/camera/image_raw" "原始相机图像，文件会很大"
    fi

    add_topic "/bluerov/camera/camera_info" "相机信息"
fi

if [ "$RECORD_RC" -eq 1 ]; then
    add_topic "/mavros/rc/in" "手柄/遥控输入"
    add_topic "/mavros/rc/out" "飞控输出到推进器的 PWM"
fi

if [ "$RECORD_BATTERY" -eq 1 ]; then
    add_topic "/mavros/battery" "电池信息"
fi

if [ "$RECORD_SONAR" -eq 1 ]; then
    if [ "$RECORD_SONAR_RAW_IMAGE" -eq 1 ]; then
        add_topic "/bluerov/sonar/image_raw" "声呐原始矩形图像"
    fi

    if [ "$RECORD_SONAR_FAN_IMAGE" -eq 1 ]; then
        add_topic "/bluerov/sonar/fan_image_raw" "声呐扇形图像"
    fi

    if [ "$RECORD_SONAR_COMPRESSED" -eq 1 ]; then
        add_topic "/bluerov/sonar/image_raw/compressed" "压缩声呐原始矩形图像"
        add_topic "/bluerov/sonar/fan_image_raw/compressed" "压缩声呐扇形图像"
    fi

    add_topic "/bluerov/sonar/camera_info" "声呐图像信息"

    if [ "$RECORD_SONAR_RANGE" -eq 1 ]; then
        add_topic "/bluerov/sonar/range_m" "声呐当前量程"
    fi

    if [ "$RECORD_SONAR_STATUS" -eq 1 ]; then
        add_topic "/bluerov/sonar/status" "声呐状态和参数"
    fi

    if [ "$RECORD_SONAR_CONTROL" -eq 1 ]; then
        add_topic "/bluerov/sonar/control" "声呐控制命令"
        add_topic "/bluerov/sonar/control_echo" "声呐控制回显"
    fi

    if [ "$RECORD_SONAR_SCAN" -eq 1 ]; then
        add_topic "/bluerov/sonar/scan" "扫描声呐 LaserScan"
    fi

    if [ "$RECORD_SONAR_POINTS" -eq 1 ]; then
        add_topic "/bluerov/sonar/points" "声呐点云 PointCloud2"
    fi
fi

if [ "$RECORD_TF" -eq 1 ]; then
    add_topic "/tf" "动态坐标变换"
    add_topic "/tf_static" "静态坐标变换"
fi

if [ "${#TOPICS[@]}" -eq 0 ]; then
    fail "没有选择任何录制话题，请检查 RECORD_xxx 配置。"
    exit 1
fi

echo
echo "============================================================"
echo "即将开始录制："
echo "保存位置：$BAG_PATH"
echo "话题数量：${#TOPICS[@]}"
echo "是否 bz2 压缩：$USE_BZ2"
echo "============================================================"
echo

for t in "${TOPICS[@]}"; do
    echo "  $t"
done

echo
echo "按 Ctrl+C 停止录制。"
echo "============================================================"
echo

if [ "$USE_BZ2" -eq 1 ]; then
    rosbag record --bz2 -O "$BAG_PATH" "${TOPICS[@]}"
else
    rosbag record -O "$BAG_PATH" "${TOPICS[@]}"
fi

echo
ok "录制结束。"
echo "查看 bag 信息："
echo "rosbag info \"$BAG_PATH\""
