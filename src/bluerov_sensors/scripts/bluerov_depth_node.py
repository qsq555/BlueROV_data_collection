#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
BlueROV Depth Node

功能：
    从 MAVROS 的压力传感器话题 /mavros/imu/static_pressure 读取压力，
    自动记录初始水面压力作为零点，
    计算当前深度，并发布：
        /bluerov/depth_m
        /bluerov/depth_marker

说明：
    1. 深度单位：m
    2. 深度方向：向下为正
    3. 默认按海水密度 1025 kg/m^3 计算
    4. 如果你在淡水池测试，可以把 fluid_density 改成 997
"""

import rospy
from sensor_msgs.msg import FluidPressure
from std_msgs.msg import Float32
from visualization_msgs.msg import Marker


class BlueROVDepthNode:
    def __init__(self):
        rospy.init_node("bluerov_depth_node")

        # -----------------------------
        # 1. 参数设置
        # -----------------------------
        # 输入压力话题，一般来自 MAVROS
        self.pressure_topic = rospy.get_param(
            "~pressure_topic",
            "/mavros/imu/static_pressure"
        )

        # 液体密度
        # 海水约 1025 kg/m^3
        # 淡水约 997 kg/m^3
        self.fluid_density = rospy.get_param("~fluid_density", 1025.0)

        # 重力加速度
        self.gravity = rospy.get_param("~gravity", 9.80665)

        # 用前多少个压力数据作为零点
        self.zero_samples = rospy.get_param("~zero_samples", 50)

        # RViz 显示用的坐标系
        # 你现在相机显示已经用了 bluerov_camera_link，
        # 所以这里先也用这个，避免 RViz TF 报错。
        self.frame_id = rospy.get_param(
            "~frame_id",
            "bluerov_camera_link"
        )

        # -----------------------------
        # 2. 内部变量
        # -----------------------------
        self.pressure_zero = None
        self.pressure_buffer = []

        # -----------------------------
        # 3. ROS 发布器
        # -----------------------------
        self.depth_pub = rospy.Publisher(
            "/bluerov/depth_m",
            Float32,
            queue_size=10
        )

        self.marker_pub = rospy.Publisher(
            "/bluerov/depth_marker",
            Marker,
            queue_size=10
        )

        # -----------------------------
        # 4. ROS 订阅器
        # -----------------------------
        self.pressure_sub = rospy.Subscriber(
            self.pressure_topic,
            FluidPressure,
            self.pressure_callback,
            queue_size=10
        )

        rospy.loginfo("BlueROV depth node started.")
        rospy.loginfo("Subscribing pressure topic: %s", self.pressure_topic)
        rospy.loginfo("Fluid density: %.2f kg/m^3", self.fluid_density)

    def pressure_callback(self, msg):
        """
        每收到一条压力数据，就计算一次深度。
        """
        pressure = msg.fluid_pressure

        # -----------------------------
        # 1. 自动估计初始零点压力
        # -----------------------------
        if self.pressure_zero is None:
            self.pressure_buffer.append(pressure)

            if len(self.pressure_buffer) < self.zero_samples:
                rospy.loginfo_throttle(
                    1.0,
                    "Calibrating pressure zero: %d / %d",
                    len(self.pressure_buffer),
                    self.zero_samples
                )
                return

            self.pressure_zero = sum(self.pressure_buffer) / len(self.pressure_buffer)

            rospy.loginfo(
                "Pressure zero calibrated: %.2f Pa",
                self.pressure_zero
            )

        # -----------------------------
        # 2. 压力换算深度
        # -----------------------------
        # 公式：
        # depth = (P - P0) / (rho * g)
        #
        # P  ：当前压力，Pa
        # P0 ：零点压力，Pa
        # rho：液体密度，kg/m^3
        # g  ：重力加速度，m/s^2
        depth = (pressure - self.pressure_zero) / (
            self.fluid_density * self.gravity
        )

        # 避免初始微小噪声导致 -0.01 这种值
        if abs(depth) < 0.01:
            depth = 0.0

        # -----------------------------
        # 3. 发布数值深度
        # -----------------------------
        depth_msg = Float32()
        depth_msg.data = depth
        self.depth_pub.publish(depth_msg)

        # -----------------------------
        # 4. 发布 RViz 文本显示
        # -----------------------------
        marker = Marker()
        marker.header.stamp = rospy.Time.now()
        marker.header.frame_id = self.frame_id

        marker.ns = "bluerov_depth"
        marker.id = 0
        marker.type = Marker.TEXT_VIEW_FACING
        marker.action = Marker.ADD

        # 文本显示在坐标系前方一点
        marker.pose.position.x = 0.0
        marker.pose.position.y = 0.0
        marker.pose.position.z = 0.5

        marker.pose.orientation.w = 1.0

        # 字体大小
        marker.scale.z = 0.2

        # 颜色：绿色
        marker.color.r = 0.0
        marker.color.g = 1.0
        marker.color.b = 0.0
        marker.color.a = 1.0

        marker.text = "Depth: %.2f m" % depth

        self.marker_pub.publish(marker)


if __name__ == "__main__":
    node = BlueROVDepthNode()
    rospy.spin()
