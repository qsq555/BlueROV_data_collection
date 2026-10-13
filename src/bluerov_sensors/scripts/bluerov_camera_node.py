#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
BlueROV UDP Camera ROS Node

功能：
    从 BlueROV Companion 发来的 UDP H264 视频流中读取图像，
    然后发布成 ROS 图像话题，供 RViz 实时显示和 rosbag 录制。

输入：
    UDP H264/RTP 视频流，默认端口 5602；QGC 默认使用 5600。

输出：
    /bluerov/camera/image_raw              sensor_msgs/Image
    /bluerov/camera/camera_info            sensor_msgs/CameraInfo
    /bluerov/camera/image_raw/compressed   sensor_msgs/CompressedImage

说明：
    这个节点不控制 ROV，只负责把视频流转换成 ROS topic。
"""

import time
import cv2
import rospy
from sensor_msgs.msg import Image, CameraInfo, CompressedImage
from cv_bridge import CvBridge


class BlueROVCameraNode:
    def __init__(self):
        rospy.init_node("bluerov_camera_node")

        # -----------------------------
        # 1. 读取 ROS 参数
        # -----------------------------
        self.port = rospy.get_param("~port", 5602)
        self.width = rospy.get_param("~width", 640)
        self.height = rospy.get_param("~height", 360)
        self.fps = rospy.get_param("~fps", 15)
        self.frame_id = rospy.get_param("~frame_id", "bluerov_camera_link")

        # 是否发布压缩图像。建议打开，录 rosbag 会小很多。
        self.publish_compressed = rospy.get_param("~publish_compressed", True)
        self.jpeg_quality = rospy.get_param("~jpeg_quality", 80)

        # -----------------------------
        # 2. 创建 ROS 发布器
        # -----------------------------
        self.bridge = CvBridge()

        self.image_pub = rospy.Publisher(
            "/bluerov/camera/image_raw",
            Image,
            queue_size=1
        )

        self.info_pub = rospy.Publisher(
            "/bluerov/camera/camera_info",
            CameraInfo,
            queue_size=1
        )

        self.compressed_pub = rospy.Publisher(
            "/bluerov/camera/image_raw/compressed",
            CompressedImage,
            queue_size=1
        )

        # -----------------------------
        # 3. GStreamer 管道
        # -----------------------------
        # 这条管道的作用：
        # udpsrc              接收 BlueROV 发来的 UDP 视频流
        # rtpjitterbuffer     缓冲网络抖动
        # rtph264depay        从 RTP 中取出 H264 数据
        # h264parse           解析 H264 数据
        # avdec_h264          软件解码 H264
        # videoconvert        转换颜色格式
        # videoscale/videorate 降分辨率和帧率，减轻 CPU 和 rosbag 压力
        # appsink             交给 OpenCV 读取
        self.pipeline = (
            f'udpsrc port={self.port} buffer-size=1048576 '
            'caps="application/x-rtp, media=(string)video, '
            'clock-rate=(int)90000, encoding-name=(string)H264, payload=(int)96" '
            '! rtpjitterbuffer latency=200 drop-on-latency=true '
            '! rtph264depay '
            '! h264parse '
            '! avdec_h264 '
            '! videoconvert '
            '! videoscale '
            '! videorate '
            f'! video/x-raw,format=BGR,width={self.width},height={self.height},framerate={self.fps}/1 '
            '! appsink drop=true max-buffers=1 sync=false'
        )

        rospy.loginfo("Opening BlueROV camera stream with pipeline:")
        rospy.loginfo(self.pipeline)

        self.cap = cv2.VideoCapture(self.pipeline, cv2.CAP_GSTREAMER)

        if not self.cap.isOpened():
            rospy.logerr("Failed to open BlueROV camera stream.")
            rospy.logerr(f"Check whether UDP {self.port} is receiving H.264/RTP and is not occupied by another receiver.")
            raise RuntimeError("Camera stream open failed")

        rospy.loginfo("BlueROV camera node started.")
        rospy.loginfo("Publishing raw image: /bluerov/camera/image_raw")
        rospy.loginfo("Publishing compressed image: /bluerov/camera/image_raw/compressed")

    def make_camera_info(self, stamp):
        """
        生成一个基础 CameraInfo。
        现在没有标定参数，所以这里只填宽高和 header。
        后续如果要做视觉定位/SLAM，需要替换成真实相机内参。
        """
        info = CameraInfo()
        info.header.stamp = stamp
        info.header.frame_id = self.frame_id
        info.width = self.width
        info.height = self.height
        return info

    def spin(self):
        while not rospy.is_shutdown():
            ret, frame = self.cap.read()

            if not ret or frame is None:
                rospy.logwarn_throttle(2.0, "No frame received from BlueROV camera stream.")
                time.sleep(0.05)
                continue

            stamp = rospy.Time.now()

            # -----------------------------
            # 1. 发布原始图像，用于 RViz 实时显示
            # -----------------------------
            image_msg = self.bridge.cv2_to_imgmsg(frame, encoding="bgr8")
            image_msg.header.stamp = stamp
            image_msg.header.frame_id = self.frame_id
            self.image_pub.publish(image_msg)

            # -----------------------------
            # 2. 发布 CameraInfo
            # -----------------------------
            info_msg = self.make_camera_info(stamp)
            self.info_pub.publish(info_msg)

            # -----------------------------
            # 3. 发布压缩图像，用于减小 rosbag
            # -----------------------------
            if self.publish_compressed:
                encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), int(self.jpeg_quality)]
                ok, encoded = cv2.imencode(".jpg", frame, encode_param)

                if ok:
                    comp_msg = CompressedImage()
                    comp_msg.header.stamp = stamp
                    comp_msg.header.frame_id = self.frame_id
                    comp_msg.format = "jpeg"
                    comp_msg.data = encoded.tobytes()
                    self.compressed_pub.publish(comp_msg)

    def shutdown(self):
        if self.cap is not None:
            self.cap.release()


if __name__ == "__main__":
    node = None
    try:
        node = BlueROVCameraNode()
        node.spin()
    except rospy.ROSInterruptException:
        pass
    finally:
        if node is not None:
            node.shutdown()
