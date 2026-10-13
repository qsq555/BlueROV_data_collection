#!/usr/bin/env bash
# -*- coding: utf-8 -*-

###############################################################################
# BlueROV 传感器一键启动脚本
#
# 功能：
#   1. 启动 roscore
#   2. 启动静态 TF
#   3. 启动 MAVROS，读取 IMU / 压力 / 电池 / RC
#   4. 启动相机节点
#   5. 启动深度节点
#   6. 启动声呐 SDK 节点，并设置声呐参数
#   7. 自动生成 RViz 配置并打开 RViz
#
# 用户日常只需要运行：
#   ./tools/start_bluerov_sensors.sh
#
# 所有开关和参数都在“用户配置区”修改，命令行启动时不需要额外输入参数。
###############################################################################

############################
# 1. 用户配置区
############################

# ROS 工作空间
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${BLUEROV_LOG_DIR:-$WS_DIR/logs}"
mkdir -p "$LOG_DIR"

# 是否检查 BlueROV 网络
CHECK_ROV_PING=1
ROV_IP="192.168.2.2"

# 是否启动各传感器/显示模块
ENABLE_IMU=1             # IMU / 电池 / RC / 压力都通过 MAVROS 读取
ENABLE_IMU_DISPLAY=1     # RViz 中显示 IMU 数值与箭头
ENABLE_CAMERA=1          # BlueROV UDP 视频流
ENABLE_DEPTH=1           # 由 /mavros/imu/static_pressure 换算深度
ENABLE_SONAR=0           # 前视声呐 SDK 采集
ENABLE_RVIZ=1            # 是否启动 RViz
ENABLE_STATIC_TF=1       # 是否发布临时静态 TF

# 坐标系配置
BASE_FRAME_ID="base_link"
CAMERA_FRAME_ID="bluerov_camera_link"
SONAR_FRAME_ID="sonar_link"

# 当前先使用零外参。后续知道真实安装位置后，修改 x y z yaw pitch roll。
CAMERA_TF_X=0
CAMERA_TF_Y=0
CAMERA_TF_Z=0
CAMERA_TF_YAW=0
CAMERA_TF_PITCH=0
CAMERA_TF_ROLL=0

SONAR_TF_X=0
SONAR_TF_Y=0
SONAR_TF_Z=0
SONAR_TF_YAW=0
SONAR_TF_PITCH=0
SONAR_TF_ROLL=0

# MAVROS 配置
MAVROS_FCU_URL="udp://:14560@"

# IMU 显示配置
IMU_DISPLAY_FRAME_ID="$CAMERA_FRAME_ID"
IMU_DISPLAY_NODE_CMD="rosrun bluerov_sensors bluerov_imu_display_node.py _imu_topic:=/mavros/imu/data _frame_id:=${IMU_DISPLAY_FRAME_ID}"

# 相机配置
CAMERA_PORT=5602  # Companion 视频副本端口；QGC 保持使用 5600
CAMERA_WIDTH=640
CAMERA_HEIGHT=360
CAMERA_FPS=15
CAMERA_NODE_CMD="rosrun bluerov_sensors bluerov_camera_node.py _port:=${CAMERA_PORT} _width:=${CAMERA_WIDTH} _height:=${CAMERA_HEIGHT} _fps:=${CAMERA_FPS} _frame_id:=${CAMERA_FRAME_ID} _publish_compressed:=true"

# 深度配置
# 海水约 1025，淡水约 997
FLUID_DENSITY=997.0
DEPTH_FRAME_ID="$CAMERA_FRAME_ID"
DEPTH_NODE_CMD="rosrun bluerov_sensors bluerov_depth_node.py _pressure_topic:=/mavros/imu/static_pressure _fluid_density:=${FLUID_DENSITY} _frame_id:=${DEPTH_FRAME_ID}"

# 声呐配置
# 说明：
#   SONAR_AUTO_CONNECT=1：节点检测到声呐后自动 Connect，相当于自动启动声呐回传
#   SONAR_FREQ=low/high：低频/高频
#   SONAR_WATER=fresh/salt：淡水/海水
#   SONAR_RANGE_M：量程，单位 m
#   SONAR_GAIN：增益，0~100
SONAR_AUTO_CONNECT=1
SONAR_RANGE_M=10
SONAR_GAIN=50
SONAR_FREQ="high"
SONAR_WATER="fresh"
SONAR_GAIN_ASSIST=0
SONAR_SPEED_OF_SOUND=1500.0

# 是否发布扇形声呐图。建议开启。
SONAR_PUBLISH_RAW_IMAGE=1
SONAR_PUBLISH_FAN_IMAGE=1
# Keep 10 m at the sonar full-sector scale without clipping the lateral beams.
SONAR_FAN_IMAGE_WIDTH=1240
SONAR_FAN_IMAGE_HEIGHT=700
SONAR_FAN_POINT_RADIUS=1

# 启动后是否再主动发送一遍声呐配置命令。建议开启，方便终端看到回显。
SONAR_SEND_CONFIG_COMMANDS=1

SONAR_NODE_CMD="rosrun bluerov_sonar_sdk run_sonar_sdk_node.sh \
_frame_id:=${SONAR_FRAME_ID} \
_default_range_m:=${SONAR_RANGE_M} \
_default_gain:=${SONAR_GAIN} \
_use_low_freq:=$( [ "$SONAR_FREQ" = "low" ] && echo true || echo false ) \
_use_fresh_water:=$( [ "$SONAR_WATER" = "fresh" ] && echo true || echo false ) \
_gain_assist:=$( [ "$SONAR_GAIN_ASSIST" -eq 1 ] && echo true || echo false ) \
_speed_of_sound:=${SONAR_SPEED_OF_SOUND} \
_auto_connect:=$( [ "$SONAR_AUTO_CONNECT" -eq 1 ] && echo true || echo false ) \
_publish_raw_image:=$( [ "$SONAR_PUBLISH_RAW_IMAGE" -eq 1 ] && echo true || echo false ) \
_publish_fan_image:=$( [ "$SONAR_PUBLISH_FAN_IMAGE" -eq 1 ] && echo true || echo false ) \
_fan_image_width:=${SONAR_FAN_IMAGE_WIDTH} \
_fan_image_height:=${SONAR_FAN_IMAGE_HEIGHT} \
_fan_point_radius:=${SONAR_FAN_POINT_RADIUS}"

# RViz 配置
RVIZ_FIXED_FRAME="$BASE_FRAME_ID"
RVIZ_CONFIG_FILE="$SCRIPT_DIR/bluerov_auto.rviz"

# RViz 中显示哪个声呐图像：fan 推荐，raw 为 SDK 原始矩形图
SONAR_RVIZ_SHOW_FAN=1
SONAR_RVIZ_SHOW_RAW=0

# 等待超时时间，单位秒
WAIT_ROSCORE_TIMEOUT=10
WAIT_MAVROS_TIMEOUT=25
WAIT_TOPIC_TIMEOUT=60
WAIT_SONAR_TIMEOUT=60

############################
# 2. 内部函数区
############################

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
NC="\033[0m"

PIDS=()

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

cleanup() {
    echo
    info "正在关闭由本脚本启动的节点..."

    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done

    ok "清理完成。"
    exit 0
}

trap cleanup SIGINT SIGTERM

source_ros_env() {
    if [ -f "/opt/ros/noetic/setup.bash" ]; then
        source /opt/ros/noetic/setup.bash
    else
        fail "未找到 /opt/ros/noetic/setup.bash，请确认 ROS Noetic 已安装。"
        exit 1
    fi

    if [ -f "$WS_DIR/devel/setup.bash" ]; then
        source "$WS_DIR/devel/setup.bash"
    else
        fail "未找到 $WS_DIR/devel/setup.bash，请先 catkin_make。"
        exit 1
    fi
}

wait_for_roscore() {
    info "等待 roscore 启动..."

    local start_time=$SECONDS

    while true; do
        if rosnode list >/dev/null 2>&1; then
            ok "roscore 已启动。"
            return 0
        fi

        if [ $((SECONDS - start_time)) -gt "$WAIT_ROSCORE_TIMEOUT" ]; then
            fail "roscore 启动超时。"
            return 1
        fi

        sleep 1
    done
}

start_roscore_if_needed() {
    if rosnode list >/dev/null 2>&1; then
        ok "检测到已有 roscore，复用当前 ROS Master。"
    else
        info "未检测到 roscore，正在启动..."
        roscore > "$LOG_DIR/roscore.log" 2>&1 &
        PIDS+=("$!")
        wait_for_roscore || exit 1
    fi
}

wait_for_topic_msg() {
    local topic="$1"
    local timeout_sec="$2"
    local name="$3"

    info "等待 ${name} 数据：${topic}"

    local start_time=$SECONDS

    while true; do
        if timeout 5 rostopic echo -n 1 --noarr "$topic" >/dev/null 2>&1; then
            ok "${name} 已有数据：${topic}"
            return 0
        fi

        if [ $((SECONDS - start_time)) -gt "$timeout_sec" ]; then
            fail "${name} 等待超时：${topic}"
            return 1
        fi

        sleep 1
    done
}

wait_mavros_connected() {
    info "等待 MAVROS 连接 BlueROV..."

    local start_time=$SECONDS

    while true; do
        local state_text
        state_text=$(timeout 2 rostopic echo -n 1 /mavros/state 2>/dev/null || true)

        if echo "$state_text" | grep -q "connected: True"; then
            ok "MAVROS 已连接 BlueROV。"
            return 0
        fi

        if [ $((SECONDS - start_time)) -gt "$WAIT_MAVROS_TIMEOUT" ]; then
            fail "MAVROS 连接超时，请检查 Companion MAVProxy 14560 输出。"
            return 1
        fi

        sleep 1
    done
}

send_sonar_command() {
    local cmd="$1"
    info "发送声呐控制命令：$cmd"
    rostopic pub -1 /bluerov/sonar/control std_msgs/String "data: '$cmd'" >/dev/null 2>&1 || {
        warn "声呐控制命令发送失败：$cmd"
        return 1
    }
    sleep 0.3
    ok "声呐控制命令已发送：$cmd"
    return 0
}

wait_sonar_frames_increase() {
    local timeout_sec="$1"
    local start_time=$SECONDS

    info "等待声呐数据帧持续增长..."

    local frames1=""
    local frames2=""

    while true; do
        local status1
        status1=$(timeout 4 rostopic echo -n 1 --noarr /bluerov/sonar/status 2>/dev/null | tr '\n' ' ' || true)
        frames1=$(echo "$status1" | sed -n 's/.*frames=\([0-9]\+\).*/\1/p')

        sleep 2

        local status2
        status2=$(timeout 4 rostopic echo -n 1 --noarr /bluerov/sonar/status 2>/dev/null | tr '\n' ' ' || true)
        frames2=$(echo "$status2" | sed -n 's/.*frames=\([0-9]\+\).*/\1/p')

        if [ -n "$frames1" ] && [ -n "$frames2" ] && [ "$frames2" -gt "$frames1" ]; then
            ok "声呐数据帧正在增长：${frames1} -> ${frames2}"
            return 0
        fi

        if [ $((SECONDS - start_time)) -gt "$timeout_sec" ]; then
            fail "声呐 frames 没有增长，当前 frames=${frames2:-unknown}"
            return 1
        fi

        warn "声呐 frames 暂未增长：${frames1:-unknown} -> ${frames2:-unknown}，继续等待..."
        sleep 1
    done
}

start_static_tfs() {
    if [ "$ENABLE_STATIC_TF" -ne 1 ]; then
        return 0
    fi

    info "启动静态 TF：${BASE_FRAME_ID} -> ${CAMERA_FRAME_ID}"
    rosrun tf2_ros static_transform_publisher \
        "$CAMERA_TF_X" "$CAMERA_TF_Y" "$CAMERA_TF_Z" \
        "$CAMERA_TF_YAW" "$CAMERA_TF_PITCH" "$CAMERA_TF_ROLL" \
        "$BASE_FRAME_ID" "$CAMERA_FRAME_ID" > "$LOG_DIR/static_tf_camera.log" 2>&1 &
    PIDS+=("$!")
    ok "静态 TF 已启动：${BASE_FRAME_ID} -> ${CAMERA_FRAME_ID}"

    if [ "$ENABLE_SONAR" -eq 1 ]; then
        info "启动静态 TF：${BASE_FRAME_ID} -> ${SONAR_FRAME_ID}"
        rosrun tf2_ros static_transform_publisher \
            "$SONAR_TF_X" "$SONAR_TF_Y" "$SONAR_TF_Z" \
            "$SONAR_TF_YAW" "$SONAR_TF_PITCH" "$SONAR_TF_ROLL" \
            "$BASE_FRAME_ID" "$SONAR_FRAME_ID" > "$LOG_DIR/static_tf_sonar.log" 2>&1 &
        PIDS+=("$!")
        ok "静态 TF 已启动：${BASE_FRAME_ID} -> ${SONAR_FRAME_ID}"
    fi
}

generate_rviz_config() {
    info "正在生成 RViz 配置：$RVIZ_CONFIG_FILE"

    cat > "$RVIZ_CONFIG_FILE" <<RVIZEOF
Panels:
  - Class: rviz/Displays
    Help Height: 78
    Name: Displays
    Property Tree Widget:
      Expanded:
        - /Global Options1
      Splitter Ratio: 0.5
    Tree Height: 700
Visualization Manager:
  Class: ""
  Displays:
    - Alpha: 0.5
      Cell Size: 1
      Class: rviz/Grid
      Color: 160; 160; 164
      Enabled: true
      Line Style:
        Line Width: 0.03
        Value: Lines
      Name: Grid
      Normal Cell Count: 0
      Offset:
        X: 0
        Y: 0
        Z: 0
      Plane: XY
      Plane Cell Count: 10
      Reference Frame: ${RVIZ_FIXED_FRAME}
      Value: true
RVIZEOF

    if [ "$ENABLE_CAMERA" -eq 1 ]; then
        cat >> "$RVIZ_CONFIG_FILE" <<RVIZEOF
    - Class: rviz/Image
      Enabled: true
      Image Topic: /bluerov/camera/image_raw
      Max Value: 1
      Median window: 5
      Min Value: 0
      Name: BlueROV Camera
      Normalize Range: true
      Queue Size: 2
      Transport Hint: raw
      Unreliable: false
      Value: true
RVIZEOF
    fi

    if [ "$ENABLE_SONAR" -eq 1 ] && [ "$SONAR_RVIZ_SHOW_FAN" -eq 1 ]; then
        cat >> "$RVIZ_CONFIG_FILE" <<RVIZEOF
    - Class: rviz/Image
      Enabled: true
      Image Topic: /bluerov/sonar/fan_image_raw
      Max Value: 1
      Median window: 5
      Min Value: 0
      Name: Sonar Fan Image
      Normalize Range: true
      Queue Size: 2
      Transport Hint: raw
      Unreliable: false
      Value: true
RVIZEOF
    fi

    if [ "$ENABLE_SONAR" -eq 1 ] && [ "$SONAR_RVIZ_SHOW_RAW" -eq 1 ]; then
        cat >> "$RVIZ_CONFIG_FILE" <<RVIZEOF
    - Class: rviz/Image
      Enabled: true
      Image Topic: /bluerov/sonar/image_raw
      Max Value: 1
      Median window: 5
      Min Value: 0
      Name: Sonar Raw Matrix
      Normalize Range: true
      Queue Size: 2
      Transport Hint: raw
      Unreliable: false
      Value: true
RVIZEOF
    fi

    if [ "$ENABLE_DEPTH" -eq 1 ]; then
        cat >> "$RVIZ_CONFIG_FILE" <<RVIZEOF
    - Class: rviz/Marker
      Enabled: true
      Marker Topic: /bluerov/depth_marker
      Name: Depth Text
      Namespaces:
        bluerov_depth: true
      Queue Size: 100
      Value: true
RVIZEOF
    fi

    if [ "$ENABLE_IMU_DISPLAY" -eq 1 ]; then
        cat >> "$RVIZ_CONFIG_FILE" <<RVIZEOF
    - Class: rviz/Marker
      Enabled: true
      Marker Topic: /bluerov/imu/text_marker
      Name: IMU Text
      Namespaces:
        bluerov_imu_text: true
      Queue Size: 100
      Value: true
    - Class: rviz/MarkerArray
      Enabled: true
      Marker Topic: /bluerov/imu/vector_markers
      Name: IMU Vectors
      Queue Size: 100
      Value: true
RVIZEOF
    fi

    cat >> "$RVIZ_CONFIG_FILE" <<RVIZEOF
  Enabled: true
  Global Options:
    Background Color: 48; 48; 48
    Fixed Frame: ${RVIZ_FIXED_FRAME}
    Frame Rate: 30
  Name: root
  Tools:
    - Class: rviz/Interact
    - Class: rviz/MoveCamera
    - Class: rviz/Select
    - Class: rviz/FocusCamera
    - Class: rviz/Measure
  Value: true
  Views:
    Current:
      Class: rviz/Orbit
      Distance: 10
      Enable Stereo Rendering:
        Stereo Eye Separation: 0.06
        Stereo Focal Distance: 1
        Swap Stereo Eyes: false
        Value: false
      Focal Point:
        X: 0
        Y: 0
        Z: 0
      Name: Current View
      Pitch: 0.5
      Target Frame: ${RVIZ_FIXED_FRAME}
      Yaw: 0.8
Window Geometry:
  Displays:
    collapsed: false
  Height: 900
  Width: 1500
  X: 50
  Y: 50
RVIZEOF

    ok "RViz 配置生成完成。"
}

############################
# 3. 主流程
############################

echo "============================================================"
echo " BlueROV 传感器一键启动"
echo "============================================================"

source_ros_env

if [ "$CHECK_ROV_PING" -eq 1 ]; then
    info "检查 BlueROV 网络：ping $ROV_IP"
    if ping -c 1 -W 1 "$ROV_IP" >/dev/null 2>&1; then
        ok "BlueROV 网络可达：$ROV_IP"
    else
        fail "无法 ping 通 BlueROV：$ROV_IP"
        echo "请检查 Ubuntu 网口是否为 192.168.2.1，ROV 是否上电。"
        exit 1
    fi
fi

start_roscore_if_needed
start_static_tfs

if [ "$ENABLE_IMU" -eq 1 ] || [ "$ENABLE_DEPTH" -eq 1 ]; then
    info "启动 MAVROS：$MAVROS_FCU_URL"
    roslaunch mavros apm.launch fcu_url:="$MAVROS_FCU_URL" > "$LOG_DIR/mavros.log" 2>&1 &
    PIDS+=("$!")

    wait_mavros_connected || exit 1

    if [ "$ENABLE_IMU" -eq 1 ]; then
        wait_for_topic_msg "/mavros/imu/data" "$WAIT_TOPIC_TIMEOUT" "IMU" || exit 1
        wait_for_topic_msg "/mavros/battery" "$WAIT_TOPIC_TIMEOUT" "电池" || true
        wait_for_topic_msg "/mavros/rc/in" "$WAIT_TOPIC_TIMEOUT" "RC 输入" || true

        if [ "$ENABLE_IMU_DISPLAY" -eq 1 ]; then
            info "启动 IMU 显示节点..."
            eval "$IMU_DISPLAY_NODE_CMD" > "$LOG_DIR/imu_display.log" 2>&1 &
            PIDS+=("$!")

            wait_for_topic_msg "/bluerov/imu/text_marker" "$WAIT_TOPIC_TIMEOUT" "IMU 数值显示 Marker" || {
                fail "IMU 显示节点启动失败，请查看日志：$LOG_DIR/imu_display.log"
                exit 1
            }

            wait_for_topic_msg "/bluerov/imu/linear_acceleration" "$WAIT_TOPIC_TIMEOUT" "IMU 加速度整理话题" || true
            wait_for_topic_msg "/bluerov/imu/angular_velocity" "$WAIT_TOPIC_TIMEOUT" "IMU 角速度整理话题" || true
        fi
    fi

    if [ "$ENABLE_DEPTH" -eq 1 ]; then
        wait_for_topic_msg "/mavros/imu/static_pressure" "$WAIT_TOPIC_TIMEOUT" "压力深度计原始数据" || exit 1
    fi
fi

if [ "$ENABLE_CAMERA" -eq 1 ]; then
    info "清理可能占用视频端口的旧进程..."
    pkill -f gst-launch 2>/dev/null || true
    pkill -f gscam 2>/dev/null || true

    info "启动相机节点..."
    eval "$CAMERA_NODE_CMD" > "$LOG_DIR/camera.log" 2>&1 &
    PIDS+=("$!")

    wait_for_topic_msg "/bluerov/camera/image_raw" "$WAIT_TOPIC_TIMEOUT" "相机图像" || {
        fail "相机节点启动失败，请查看日志：$LOG_DIR/camera.log"
        exit 1
    }

    wait_for_topic_msg "/bluerov/camera/image_raw/compressed" "$WAIT_TOPIC_TIMEOUT" "压缩相机图像" || true
fi

if [ "$ENABLE_DEPTH" -eq 1 ]; then
    info "启动深度换算节点..."
    eval "$DEPTH_NODE_CMD" > "$LOG_DIR/depth.log" 2>&1 &
    PIDS+=("$!")

    wait_for_topic_msg "/bluerov/depth_m" "$WAIT_TOPIC_TIMEOUT" "换算深度" || {
        fail "深度节点启动失败，请查看日志：$LOG_DIR/depth.log"
        exit 1
    }
fi

if [ "$ENABLE_SONAR" -eq 1 ]; then
    info "关闭可能残留的声呐节点..."
    pkill -f sonar_sdk_node 2>/dev/null || true
    sleep 1

    info "启动声呐 SDK 节点..."
    eval "$SONAR_NODE_CMD" > "$LOG_DIR/sonar.log" 2>&1 &
    PIDS+=("$!")

    wait_for_topic_msg "/bluerov/sonar/status" "$WAIT_SONAR_TIMEOUT" "声呐状态" || {
        fail "声呐节点启动失败，请查看日志：$LOG_DIR/sonar.log"
        exit 1
    }

    if [ "$SONAR_SEND_CONFIG_COMMANDS" -eq 1 ]; then
        info "按稳定顺序初始化声呐：stop -> 参数 -> start"

        # 这个顺序与手动恢复成功流程一致，可避免 SDK 处于“已连接但不出帧”的状态。
        send_sonar_command "stop" || true
        sleep 1

        send_sonar_command "$SONAR_WATER" || true
        send_sonar_command "$SONAR_FREQ" || true
        send_sonar_command "range ${SONAR_RANGE_M}" || true
        send_sonar_command "gain ${SONAR_GAIN}" || true
        if [ "$SONAR_GAIN_ASSIST" -eq 1 ]; then
            send_sonar_command "gain_assist on" || true
        else
            send_sonar_command "gain_assist off" || true
        fi
        send_sonar_command "speed ${SONAR_SPEED_OF_SOUND}" || true

        sleep 1
        if [ "$SONAR_AUTO_CONNECT" -eq 1 ]; then
            send_sonar_command "start" || true
            sleep 2
        fi
    fi

    wait_sonar_frames_increase "$WAIT_SONAR_TIMEOUT" || {
        warn "第一次启动后声呐帧未增长，按低频安全配置自动重试一次..."
        send_sonar_command "stop" || true
        sleep 1
        send_sonar_command "$SONAR_WATER" || true
        send_sonar_command "low" || true
        send_sonar_command "range ${SONAR_RANGE_M}" || true
        send_sonar_command "gain ${SONAR_GAIN}" || true
        send_sonar_command "gain_assist off" || true
        send_sonar_command "speed ${SONAR_SPEED_OF_SOUND}" || true
        sleep 1
        send_sonar_command "start" || true
        sleep 2

        wait_sonar_frames_increase "$WAIT_SONAR_TIMEOUT" || {
            fail "声呐 SDK 没有持续输出帧，请查看日志：$LOG_DIR/sonar.log"
            exit 1
        }
    }

    if [ "$SONAR_PUBLISH_RAW_IMAGE" -eq 1 ]; then
        wait_for_topic_msg "/bluerov/sonar/image_raw" "$WAIT_SONAR_TIMEOUT" "声呐原始矩形图像" || {
            fail "声呐没有输出 /bluerov/sonar/image_raw，请查看日志：$LOG_DIR/sonar.log"
            exit 1
        }
    fi

    if [ "$SONAR_PUBLISH_FAN_IMAGE" -eq 1 ]; then
        wait_for_topic_msg "/bluerov/sonar/fan_image_raw" "$WAIT_SONAR_TIMEOUT" "声呐扇形图像" || {
            fail "声呐没有输出 /bluerov/sonar/fan_image_raw，请查看日志：$LOG_DIR/sonar.log"
            exit 1
        }
    fi

    wait_for_topic_msg "/bluerov/sonar/range_m" "$WAIT_SONAR_TIMEOUT" "声呐量程" || true
fi

if [ "$ENABLE_RVIZ" -eq 1 ]; then
    generate_rviz_config
    info "启动 RViz..."
    rviz -d "$RVIZ_CONFIG_FILE" > "$LOG_DIR/rviz.log" 2>&1 &
    PIDS+=("$!")
    ok "RViz 已启动，配置文件：$RVIZ_CONFIG_FILE"
fi

echo
echo "============================================================"
ok "BlueROV 传感器系统启动完成。"
echo "已启动内容："
echo "  ENABLE_IMU          = $ENABLE_IMU"
echo "  ENABLE_IMU_DISPLAY  = $ENABLE_IMU_DISPLAY"
echo "  ENABLE_CAMERA       = $ENABLE_CAMERA"
echo "  ENABLE_DEPTH        = $ENABLE_DEPTH"
echo "  ENABLE_SONAR        = $ENABLE_SONAR"
echo "  ENABLE_RVIZ         = $ENABLE_RVIZ"
echo
echo "声呐当前配置："
echo "  SONAR_RANGE_M       = $SONAR_RANGE_M"
echo "  SONAR_GAIN          = $SONAR_GAIN"
echo "  SONAR_FREQ          = $SONAR_FREQ"
echo "  SONAR_WATER         = $SONAR_WATER"
echo "  FAN_IMAGE_TOPIC     = /bluerov/sonar/fan_image_raw"
echo
echo "日志文件位置："
echo "  $LOG_DIR/mavros.log"
echo "  $LOG_DIR/camera.log"
echo "  $LOG_DIR/depth.log"
echo "  $LOG_DIR/imu_display.log"
echo "  $LOG_DIR/sonar.log"
echo "  $LOG_DIR/rviz.log"
echo
echo "按 Ctrl+C 可关闭本脚本启动的节点。"
echo "============================================================"

while true; do
    sleep 1
done
