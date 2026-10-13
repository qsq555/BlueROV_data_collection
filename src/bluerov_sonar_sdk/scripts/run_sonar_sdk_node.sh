#!/usr/bin/env bash
set -euo pipefail

# The calling BlueROV workspace must already be sourced.
source /opt/ros/noetic/setup.bash

PKG_DIR="$(rospack find bluerov_sonar_sdk)"
QT514_DIR="${QT514_DIR:-$HOME/Qt/5.14.2/gcc_64}"
SDK_LIB_DIR="$PKG_DIR/third_party/ForwardlookingSonarSDK/lib"

if [[ ! -d "$QT514_DIR/lib" ]]; then
  echo "Qt 5.14.2 runtime not found at $QT514_DIR; install Qt 5.14.2 or set QT514_DIR." >&2
  exit 1
fi
if [[ ! -f "$SDK_LIB_DIR/libForwardlookingSonarSDK.so" ]]; then
  echo "ForwardlookingSonarSDK library not found at $SDK_LIB_DIR." >&2
  exit 1
fi

export PATH="$QT514_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$QT514_DIR/lib:$SDK_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec rosrun bluerov_sonar_sdk sonar_sdk_node "$@"
