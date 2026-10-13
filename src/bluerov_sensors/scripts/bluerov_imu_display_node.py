#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
BlueROV IMU Display Node

功能：
    订阅 MAVROS IMU 数据：
        /mavros/imu/data

    提取：
        linear_acceleration.x/y/z
        angular_velocity.x/y/z

    发布：
        /bluerov/imu/linear_acceleration
        /bluerov/imu/angular_velocity
        /bluerov/imu/text_marker
        /bluerov/imu/vector_markers

用途：
    1. 在 RViz 中实时显示 IMU 数值；
    2. 在 RViz 中用箭头显示加速度和角速度方向；
    3. 方便 rosbag 录制整理后的 IMU 数据。
"""

import math
import rospy

from sensor_msgs.msg import Imu
from geometry_msgs.msg import Vector3Stamped, Point
from visualization_msgs.msg import Marker, MarkerArray


class BlueROVIMUDisplayNode:
    def __init__(self):
        rospy.init_node("bluerov_imu_display_node")

        # -----------------------------
        # 1. 参数
        # -----------------------------
        self.imu_topic = rospy.get_param("~imu_topic", "/mavros/imu/data")

        # RViz 显示使用的坐标系。
        # 为了避免 TF 报错，默认用你前面已经在 RViz 里使用的 bluerov_camera_link。
        # 如果后面整理 TF，可以改成 imu_link 或 base_link。
        self.frame_id = rospy.get_param("~frame_id", "bluerov_camera_link")

        # 箭头缩放系数
        self.accel_scale = rospy.get_param("~accel_scale", 0.05)
        self.gyro_scale = rospy.get_param("~gyro_scale", 0.30)

        # -----------------------------
        # 2. 发布器
        # -----------------------------
        self.accel_pub = rospy.Publisher(
            "/bluerov/imu/linear_acceleration",
            Vector3Stamped,
            queue_size=10
        )

        self.gyro_pub = rospy.Publisher(
            "/bluerov/imu/angular_velocity",
            Vector3Stamped,
            queue_size=10
        )

        self.text_marker_pub = rospy.Publisher(
            "/bluerov/imu/text_marker",
            Marker,
            queue_size=10
        )

        self.vector_marker_pub = rospy.Publisher(
            "/bluerov/imu/vector_markers",
            MarkerArray,
            queue_size=10
        )

        # -----------------------------
        # 3. 订阅 MAVROS IMU
        # -----------------------------
        self.imu_sub = rospy.Subscriber(
            self.imu_topic,
            Imu,
            self.imu_callback,
            queue_size=20
        )

        rospy.loginfo("BlueROV IMU display node started.")
        rospy.loginfo("Subscribing IMU topic: %s", self.imu_topic)
        rospy.loginfo("RViz frame_id: %s", self.frame_id)

    def imu_callback(self, msg):
        stamp = rospy.Time.now()

        ax = msg.linear_acceleration.x
        ay = msg.linear_acceleration.y
        az = msg.linear_acceleration.z

        wx = msg.angular_velocity.x
        wy = msg.angular_velocity.y
        wz = msg.angular_velocity.z

        # rad/s 转 deg/s，便于阅读
        wx_deg = wx * 180.0 / math.pi
        wy_deg = wy * 180.0 / math.pi
        wz_deg = wz * 180.0 / math.pi

        # -----------------------------
        # 1. 发布整理后的加速度
        # -----------------------------
        accel_msg = Vector3Stamped()
        accel_msg.header.stamp = stamp
        accel_msg.header.frame_id = self.frame_id
        accel_msg.vector.x = ax
        accel_msg.vector.y = ay
        accel_msg.vector.z = az
        self.accel_pub.publish(accel_msg)

        # -----------------------------
        # 2. 发布整理后的角速度
        # -----------------------------
        gyro_msg = Vector3Stamped()
        gyro_msg.header.stamp = stamp
        gyro_msg.header.frame_id = self.frame_id
        gyro_msg.vector.x = wx
        gyro_msg.vector.y = wy
        gyro_msg.vector.z = wz
        self.gyro_pub.publish(gyro_msg)

        # -----------------------------
        # 3. 发布 RViz 文字 Marker
        # -----------------------------
        text_marker = Marker()
        text_marker.header.stamp = stamp
        text_marker.header.frame_id = self.frame_id

        text_marker.ns = "bluerov_imu_text"
        text_marker.id = 0
        text_marker.type = Marker.TEXT_VIEW_FACING
        text_marker.action = Marker.ADD

        text_marker.pose.position.x = 0.0
        text_marker.pose.position.y = 0.0
        text_marker.pose.position.z = 1.0
        text_marker.pose.orientation.w = 1.0

        text_marker.scale.z = 0.18

        text_marker.color.r = 0.0
        text_marker.color.g = 1.0
        text_marker.color.b = 1.0
        text_marker.color.a = 1.0

        text_marker.text = (
            "IMU\n"
            "Accel [m/s^2]\n"
            "  ax: %+7.3f\n"
            "  ay: %+7.3f\n"
            "  az: %+7.3f\n"
            "Gyro [rad/s]\n"
            "  wx: %+7.3f\n"
            "  wy: %+7.3f\n"
            "  wz: %+7.3f\n"
            "Gyro [deg/s]\n"
            "  wx: %+7.2f\n"
            "  wy: %+7.2f\n"
            "  wz: %+7.2f"
            % (ax, ay, az, wx, wy, wz, wx_deg, wy_deg, wz_deg)
        )

        self.text_marker_pub.publish(text_marker)

        # -----------------------------
        # 4. 发布 RViz 箭头 MarkerArray
        # -----------------------------
        marker_array = MarkerArray()

        accel_marker = self.make_arrow_marker(
            marker_id=0,
            ns="bluerov_imu_accel",
            start_y=-0.35,
            vx=ax * self.accel_scale,
            vy=ay * self.accel_scale,
            vz=az * self.accel_scale,
            r=0.0,
            g=1.0,
            b=0.0,
            text="accel"
        )

        gyro_marker = self.make_arrow_marker(
            marker_id=1,
            ns="bluerov_imu_gyro",
            start_y=0.35,
            vx=wx * self.gyro_scale,
            vy=wy * self.gyro_scale,
            vz=wz * self.gyro_scale,
            r=1.0,
            g=0.5,
            b=0.0,
            text="gyro"
        )

        marker_array.markers.append(accel_marker)
        marker_array.markers.append(gyro_marker)

        self.vector_marker_pub.publish(marker_array)

    def make_arrow_marker(self, marker_id, ns, start_y, vx, vy, vz, r, g, b, text):
        """
        生成一个 RViz 箭头 Marker。
        箭头起点固定，终点由 vx/vy/vz 决定。
        """
        marker = Marker()
        marker.header.stamp = rospy.Time.now()
        marker.header.frame_id = self.frame_id

        marker.ns = ns
        marker.id = marker_id
        marker.type = Marker.ARROW
        marker.action = Marker.ADD

        start = Point()
        start.x = 0.0
        start.y = start_y
        start.z = 0.0

        end = Point()
        end.x = vx
        end.y = start_y + vy
        end.z = vz

        marker.points.append(start)
        marker.points.append(end)

        # scale.x：箭杆直径
        # scale.y：箭头直径
        # scale.z：箭头长度
        marker.scale.x = 0.03
        marker.scale.y = 0.07
        marker.scale.z = 0.12

        marker.color.r = r
        marker.color.g = g
        marker.color.b = b
        marker.color.a = 1.0

        return marker


if __name__ == "__main__":
    node = BlueROVIMUDisplayNode()
    rospy.spin()
