cmake_minimum_required(VERSION 3.0.2)
project(bluerov_sensors)

find_package(catkin REQUIRED COMPONENTS
  cv_bridge
  geometry_msgs
  rospy
  sensor_msgs
  std_msgs
  visualization_msgs
)

catkin_package(
  CATKIN_DEPENDS cv_bridge geometry_msgs rospy sensor_msgs std_msgs visualization_msgs
)

catkin_install_python(PROGRAMS
  scripts/bluerov_camera_node.py
  scripts/bluerov_depth_node.py
  scripts/bluerov_imu_display_node.py
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)
