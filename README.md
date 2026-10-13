# BlueROV 采集工作区

这份工作区整理了当前已验证的 BlueROV 传感器采集、RViz 显示和 rosbag 录制配置。ROV 的运动仍由 QGroundControl（QGC）和遥控器控制；这里的 ROS 节点只接收 MAVLink/传感器数据，不向飞控发送运动指令。

## 当前复现范围

当前配置包含：

- MAVROS：飞控连接状态、IMU、压力、RC 和电池数据，默认监听 UDP 14560。
- Companion 视频复制：QGC 继续接收 UDP 5600，ROS 相机节点接收 UDP 5602。
- 相机 ROS 话题：原始图、JPEG 压缩图和未标定的 CameraInfo。
- 压力深度换算、IMU 可视化、静态 TF 和 RViz。
- rosbag 默认录制 MAVROS 状态/IMU/压力/RC/电池、深度、IMU 显示、压缩相机图、CameraInfo 和 TF。
- 声呐当前默认关闭。厂家 SDK/二进制不在仓库中；需要声呐时，须另行取得可合法使用的 SDK 并配置对应 ROS 包。

本配置曾在当前工作站连接 BlueROV 时验证过 MAVROS 和相机话题。离线构建不代表目标设备的网络、视频流和飞控转发已经验证；第一次在新设备部署时按下方步骤检查。

## 系统要求

目标环境为 Ubuntu 20.04 x86_64、ROS Noetic。为保持一致，建议使用该版本组合。先安装 ROS Noetic Desktop Full，并配置 ROS 软件源：

    https://wiki.ros.org/noetic/Installation/Ubuntu

Noetic 已结束上游维护，安装时 apt 软件源的可用性取决于目标系统的软件源配置。

## 克隆、安装依赖和编译

克隆独立仓库：

    git clone https://github.com/qsq555/BlueROV_data_collection.git
    cd BlueROV_data_collection

先安装 ROS Noetic，再运行本目录的依赖脚本：

    ./scripts/install_dependencies_ubuntu20.sh

构建当前采集工作区：

    source /opt/ros/noetic/setup.bash
    catkin_make

每个新终端运行 ROS 命令前加载工作区：

    source /opt/ros/noetic/setup.bash
    source devel/setup.bash

## 网络和视频配置

本机已验证的有线网络地址为 topside 电脑 192.168.2.1/24、BlueROV Companion 192.168.2.2。另一台电脑要把有线网口配置到同一网段，并在 Companion 视频配置中把目标地址改为新电脑的有线网口 IP。

在 Companion 相机页面 http://192.168.2.2:2770/camera 中保留现有编码管线，只把原先发往 QGC 的 RTP sink 改为向两个 UDP 端口发送：

    ! rtph264pay config-interval=10 pt=96 ! multiudpsink clients=192.168.2.1:5600,192.168.2.1:5602

仓库中的 config/companion/gstreamer2.param 有这段设置。将其中的 192.168.2.1 替换为目标电脑地址，保存后重启 Companion 视频流。QGC 使用 5600，ROS 节点使用 5602；不要让另一个视频接收进程占用 5602。

MAVROS 配置默认在本机 UDP 14560 等待 Companion 转发的 MAVLink。若目标设备使用不同的转发地址或端口，修改 tools/start_bluerov_sensors.sh 顶部 MAVROS_FCU_URL 和 Companion 的 MAVLink 输出设置，使两者匹配。启动前确认 QGC 可以连接飞控。Ubuntu 20.04 上请使用 QGC 4.4 系列；本仓库不分发 QGC 二进制。按 [QGC 4.4 安装说明](https://docs.qgroundcontrol.com/v4.4.3/en/qgc-user-guide/getting_started/download_and_install.html) 从官方页面取得 AppImage。

## 启动和录制

终端一启动 MAVROS、传感器节点及 RViz：

    cd BlueROV_data_collection
    source /opt/ros/noetic/setup.bash
    source devel/setup.bash
    ./tools/start_bluerov_sensors.sh

等待终端报告启动完成，并检查 RViz 中的相机和 IMU/深度显示。

终端二开始录制：

    cd BlueROV_data_collection
    source /opt/ros/noetic/setup.bash
    source devel/setup.bash
    ./tools/record_bluerov_bag.sh

录制终端按 Ctrl+C 停止并等待 rosbag 写完，然后再在启动终端按 Ctrl+C 关闭节点。

默认数据目录是 ~/bluerov_bag。更改保存位置可在启动录制时设置环境变量，例如：

    BLUEROV_BAG_DIR=/mnt/data/bluerov ./tools/record_bluerov_bag.sh

也可以编辑 tools/record_bluerov_bag.sh 中的 BAG_PREFIX、BAG_DIR、压缩和话题开关。相机默认只录 JPEG 压缩图，避免 bag 文件过大。实际文件名带有时间戳。

## 当前标定状态和边界

- 深度节点启动后取前 50 个压力样本的均值作为压力零点；当前流体密度配置为淡水 997 kg/m³。
- 相机和声呐 TF 的外参目前为零；CameraInfo 只有图像尺寸，没有相机内参标定。
- 外参尚未标定，当前话题可用于记录和检查，不应把零外参当成标定结果。
- 声呐相关开关留在启动/录制脚本中但默认关闭。没有厂家 SDK 时不要打开 ENABLE_SONAR 或 RECORD_SONAR。
- QGC 程序、QGC 用户配置、手柄校准值、系统镜像、录制 bag 和运行日志均未上传。每台电脑都要分别安装 QGC，并在连接 F310 后进入 Vehicle Setup → Joystick，选择活动手柄并按界面向导校准，最后检查各轴和按键。[QGC 摇杆配置说明](https://docs.qgroundcontrol.com/Stable_V4.4/en/qgc-user-guide/setup_view/joystick.html) 有完整步骤。

## 新设备检查

1. 确认有线网卡地址与 Companion 地址同网段，并能访问 Companion。
2. 确认 QGC 能连接飞控且仍能显示视频。
3. 运行传感器脚本，确认启动日志显示 MAVROS connected，并等待相机图像话题。
4. 新终端执行 rostopic hz /bluerov/camera/image_raw 和 rostopic hz /mavros/imu/data，确认有数据。
5. 运行录制脚本；用 rosbag info 检查录制的话题和时长。

相机无画面时，检查 Companion 是否同时向新电脑的 5600 和 5602 发流、相机节点日志及本机 UDP 5602。MAVROS 连接超时时，检查 Companion MAVLink 输出端口是否与 MAVROS_FCU_URL 一致。运行日志写入本目录 logs/。

## 文件说明

- src/bluerov_sensors/：相机、压力深度和 IMU 显示 ROS 节点。
- tools/start_bluerov_sensors.sh：启动和设备参数。
- tools/record_bluerov_bag.sh：bag 话题、压缩和保存目录配置。
- tools/bluerov_auto.rviz：RViz 配置。
- config/companion/gstreamer2.param：视频复制的 sink 配置示例。
