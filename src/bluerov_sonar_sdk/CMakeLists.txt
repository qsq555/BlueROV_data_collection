cmake_minimum_required(VERSION 3.0.2)
project(bluerov_sonar_sdk)

add_compile_options(-std=c++14)

find_package(catkin REQUIRED COMPONENTS
  roscpp
  sensor_msgs
  std_msgs
  image_transport
)

# The vendor SDK binary requires Qt_5.14 symbols. Prefer the Qt installation
# documented for this project over Ubuntu 20.04's system Qt 5.12.
if(DEFINED ENV{QT514_DIR} AND NOT "$ENV{QT514_DIR}" STREQUAL "")
  set(_qt514_root "$ENV{QT514_DIR}")
else()
  set(_qt514_root "$ENV{HOME}/Qt/5.14.2/gcc_64")
endif()
if(NOT EXISTS "${_qt514_root}/lib/cmake/Qt5/Qt5Config.cmake")
  message(FATAL_ERROR "Qt 5.14.2 not found at ${_qt514_root}. Install Qt 5.14.2 GCC 64-bit with Qt Serial Port, or set QT514_DIR.")
endif()
set(Qt5_DIR "${_qt514_root}/lib/cmake/Qt5" CACHE PATH "Qt 5.14 package location" FORCE)
foreach(_qt_component Core Network Gui Widgets SerialPort)
  set(Qt5${_qt_component}_DIR "${_qt514_root}/lib/cmake/Qt5${_qt_component}" CACHE PATH "Qt 5.14 ${_qt_component} package location" FORCE)
endforeach()
find_package(Qt5 5.14 REQUIRED COMPONENTS Core Network Widgets Gui SerialPort)

catkin_package(
  CATKIN_DEPENDS roscpp sensor_msgs std_msgs image_transport
)

set(SDK_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ForwardlookingSonarSDK)

include_directories(
  ${catkin_INCLUDE_DIRS}
  ${SDK_DIR}/include
)

add_executable(sonar_sdk_node
  src/sonar_sdk_node.cpp
)

target_link_libraries(sonar_sdk_node
  ${catkin_LIBRARIES}
  Qt5::Core
  Qt5::Network
  Qt5::Widgets
  Qt5::Gui
  Qt5::SerialPort
  ${SDK_DIR}/lib/libForwardlookingSonarSDK.so
)

install(TARGETS sonar_sdk_node
  RUNTIME DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(PROGRAMS
  scripts/run_sonar_sdk_node.sh
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)
