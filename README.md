# BlueROV 采集工作区

这份工作区整理了当前已验证的 BlueROV 传感器采集、RViz 显示和 rosbag 录制配置。ROV 的运动仍由 QGroundControl（QGC）和遥控器控制；这里的 ROS 节点只接收 MAVLink/传感器数据，不向飞控发送运动指令。

## 当前复现范围

当前配置包含：

- MAVROS：飞控连接状态、IMU、压力、RC 和电池数据，默认监听 UDP 14560。
- Companion 视频复制：QGC 继续接收 UDP 5600，ROS 相机节点接收 UDP 5602。
- 相机 ROS 话题：原始图、JPEG 压缩图和未标定的 CameraInfo。
- 压力深度换算、IMU 可视化、静态 TF 和 RViz。
- rosbag 默认录制 MAVROS 状态/IMU/压力/RC/电池、深度、IMU 显示、压缩相机图、CameraInfo 和 TF。
- Oculus 前视声呐支持作为可选功能随 ROS 封装提供；启动和录制默认关闭，以便无声呐时仍可运行。启用前需要声呐硬件已连接，并安装 Qt 5.14.2 运行库。

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

声呐动态库依赖 Qt 5.14 ABI。请使用 Qt 安装器安装 Qt 5.14.2 的 GCC 64-bit 组件及 Qt Serial Port，默认安装路径为 `~/Qt/5.14.2/gcc_64`。安装到其他目录时，在编译和启动前设置 `export QT514_DIR=/实际路径`。ROS 封装的 CMake 会优先使用此 Qt 路径，避免误链接 Ubuntu 20.04 的 Qt 5.12。Qt 5.14.2 安装中提供相应编译配置和运行库；依赖脚本安装 ROS 及相机节点所需的软件包。

构建当前采集工作区：

    source /opt/ros/noetic/setup.bash
    catkin_make

每个新终端运行 ROS 命令前加载工作区：

    source /opt/ros/noetic/setup.bash
    source devel/setup.bash

## 网络和视频配置

本机已验证的有线网络地址为 topside 电脑 192.168.2.1/24、BlueROV Companion 192.168.2.2。每台新电脑部署前，按下表检查需要替换的地址、端口和保存目录：

| 项目 | 配置位置 | 新设备上的调整方法 |
| --- | --- | --- |
| topside 有线网卡 IP | Ubuntu 网络设置；`config/companion/gstreamer2.param`；Companion 相机页面 | 给电脑有线网卡配置与 Companion 同网段且未占用的地址（示例 `192.168.2.1/24`）。把视频管线两个 `clients=` 地址都改成该电脑 IP。 |
| Companion IP | `tools/start_bluerov_sensors.sh` 的 `ROV_IP`；Companion 页面地址 | 默认是 `192.168.2.2`。如果 Companion 地址不同，修改 `ROV_IP`，并使用新地址打开相机配置页面。 |
| ROS 视频端口 | `tools/start_bluerov_sensors.sh` 的 `CAMERA_PORT`；Companion 视频 sink | 默认 ROS 使用 UDP 5602，QGC 使用 5600。若改端口，两边必须一致；避免其他进程占用 ROS 端口。 |
| MAVLink 转发 | `tools/start_bluerov_sensors.sh` 的 `MAVROS_FCU_URL`；Companion MAVLink 输出 | 默认本机监听 UDP 14560（`udp://:14560@`）。若更改端口或目标电脑 IP，要同步修改 Companion 的 MAVLink 转发目标。 |
| rosbag 保存目录 | `BLUEROV_BAG_DIR` 环境变量；`tools/record_bluerov_bag.sh` | 默认 `~/bluerov_bag`。可按下文示例设置到数据盘。 |
| Qt 安装目录 | `QT514_DIR` 环境变量 | 默认 `~/Qt/5.14.2/gcc_64`；Qt 安装在其他位置时，在编译及运行前设置为实际目录。 |

相机和声呐外参目前是零值，尚未标定；只有获得实测外参后才修改启动脚本中的 `CAMERA_TF_*` 和 `SONAR_TF_*`。

在 Companion 相机页面 http://192.168.2.2:2770/camera 中保留现有编码管线，只把原先发往 QGC 的 RTP sink 改为向两个 UDP 端口发送：

    ! rtph264pay config-interval=10 pt=96 ! multiudpsink clients=192.168.2.1:5600,192.168.2.1:5602

仓库中的 config/companion/gstreamer2.param 有这段设置。将其中的 192.168.2.1 替换为目标电脑地址，保存后重启 Companion 视频流。QGC 使用 5600，ROS 节点使用 5602；不要让另一个视频接收进程占用 5602。

MAVROS 配置默认在本机 UDP 14560 等待 Companion 转发的 MAVLink。若目标设备使用不同的转发地址或端口，按上表同步修改 `MAVROS_FCU_URL` 和 Companion 的 MAVLink 输出设置。

## 安装 QGC 与校准摇杆

本仓库不包含 QGC 程序和每台电脑的 QGC 用户配置。Ubuntu 20.04 x86_64 建议使用 QGC 4.4.3 AppImage。按 [QGC 官方 Ubuntu 安装教程](https://docs.qgroundcontrol.com/v4.4.3/en/qgc-user-guide/getting_started/download_and_install.html) 下载；可按以下步骤安装运行：

1. 安装视频和 AppImage 运行依赖：

       sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl libqt5gui5 libfuse2 -y

2. 从上述官方页面下载 `QGroundControl.AppImage`，在下载目录运行：

       chmod +x QGroundControl.AppImage
       ./QGroundControl.AppImage

3. 官方 Linux 安装步骤还建议把当前用户加入 `dialout` 组并移除 `modemmanager`，以支持直接使用串口连接飞控：

       sudo usermod -a -G dialout "$USER"
       sudo apt-get remove modemmanager -y

   完成后注销并重新登录。当前工作流通过以太网从 Companion 接收 MAVLink；只有电脑需要直接连接 USB/串口飞控时才需要这些串口配置。

4. 如需使用 Logitech F310，先连接手柄并在 QGC 中连接飞控，打开 **Vehicle Setup → Joystick**，选择活动手柄并按校准向导完成轴和按键校准。确认各轴方向正确后再操作飞行器；校准保存在本机，不随仓库共享。详见 [QGC 官方摇杆设置教程](https://docs.qgroundcontrol.com/Stable_V4.4/en/qgc-user-guide/setup_view/joystick.html)。

## 启动和录制

终端一启动 MAVROS、传感器节点及 RViz：

    cd BlueROV_data_collection
    source /opt/ros/noetic/setup.bash
    source devel/setup.bash
    ./tools/start_bluerov_sensors.sh

等待终端报告启动完成，并检查 RViz 中的相机和 IMU/深度显示。

声呐已连接且处于水下时，编辑 `tools/start_bluerov_sensors.sh`，将 `ENABLE_SONAR=0` 改为 `ENABLE_SONAR=1`；编辑 `tools/record_bluerov_bag.sh`，将 `RECORD_SONAR=0` 改为 `RECORD_SONAR=1`。启动脚本会连接声呐、设置量程和增益，并等待声呐数据帧；随后正常运行录制脚本即可把声呐图像、量程、状态及控制回显写入 bag。声呐未连接时保持这两个开关为 0。

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
- 声呐启动和录制开关默认关闭，避免声呐未连接时启动等待超时。按上节说明同时打开 `ENABLE_SONAR` 和 `RECORD_SONAR` 后才会采集声呐话题。
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
- src/bluerov_sonar_sdk/：Oculus 声呐 ROS 封装及随项目授权提供的 SDK 文件；运行需要 Qt 5.14.2。
- tools/start_bluerov_sensors.sh：启动和设备参数。
- tools/record_bluerov_bag.sh：bag 话题、压缩和保存目录配置。
- tools/bluerov_auto.rviz：RViz 配置。
- config/companion/gstreamer2.param：视频复制的 sink 配置示例。
