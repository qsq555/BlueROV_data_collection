#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/os-release ]] || ! grep -q 'VERSION_ID="20.04"' /etc/os-release; then
  echo "This dependency list targets Ubuntu 20.04 with ROS Noetic." >&2
  exit 1
fi
if [[ ! -f /opt/ros/noetic/setup.bash ]]; then
  echo "Install ROS Noetic Desktop Full first: https://wiki.ros.org/noetic/Installation/Ubuntu" >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y \
  python3-opencv \
  gstreamer1.0-libav \
  gstreamer1.0-plugins-bad \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-ugly \
  gstreamer1.0-tools \
  ros-noetic-cv-bridge \
  ros-noetic-geometry-msgs \
  ros-noetic-mavros \
  ros-noetic-mavros-extras \
  ros-noetic-rosbag \
  ros-noetic-rviz \
  ros-noetic-sensor-msgs \
  ros-noetic-std-msgs \
  ros-noetic-tf2-ros \
  ros-noetic-visualization-msgs \
  ros-noetic-catkin
