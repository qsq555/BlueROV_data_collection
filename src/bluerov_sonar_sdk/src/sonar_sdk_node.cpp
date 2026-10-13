#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cctype>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

#include <QCoreApplication>
#include <QObject>
#include <QTimer>
#include <QString>
#include <QMap>

#include <ros/ros.h>
#include <std_msgs/String.h>
#include <std_msgs/Float32.h>
#include <sensor_msgs/Image.h>
#include <sensor_msgs/CameraInfo.h>
#include <image_transport/image_transport.h>

#include "forwardlookingsonarsdk.h"
#include "bhsonar.h"

static QString ipToString(uint32_t ip)
{
    unsigned char ip1 = static_cast<unsigned char>(ip & 0xff);
    unsigned char ip2 = static_cast<unsigned char>((ip & 0xff00) >> 8);
    unsigned char ip3 = static_cast<unsigned char>((ip & 0xff0000) >> 16);
    unsigned char ip4 = static_cast<unsigned char>((ip & 0xff000000) >> 24);

    return QString("%1.%2.%3.%4")
            .arg((int)ip1)
            .arg((int)ip2)
            .arg((int)ip3)
            .arg((int)ip4);
}

static std::string trimLower(const std::string& input)
{
    size_t first = input.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return "";
    }

    size_t last = input.find_last_not_of(" \t\r\n");
    std::string out = input.substr(first, last - first + 1);

    std::transform(out.begin(), out.end(), out.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    return out;
}

class BlueROVSonarNode : public QObject
{
public:
    BlueROVSonarNode(ros::NodeHandle& nh, ros::NodeHandle& pnh)
        : QObject(nullptr),
          nh_(nh),
          pnh_(pnh),
          it_(nh_)
    {
        pnh_.param<std::string>("frame_id", frame_id_, std::string("sonar_link"));

        pnh_.param<double>("default_range_m", range_m_, 10.0);
        pnh_.param<int>("default_gain", gain_, 50);
        pnh_.param<bool>("use_low_freq", use_low_freq_, true);
        pnh_.param<bool>("use_fresh_water", use_fresh_water_, true);
        pnh_.param<bool>("gain_assist", gain_assist_, false);
        pnh_.param<double>("speed_of_sound", speed_of_sound_, 1500.0);

        pnh_.param<bool>("auto_connect", auto_connect_, true);
        pnh_.param<int>("connect_retry_ms", connect_retry_ms_, 3000);

        pnh_.param<bool>("publish_raw_image", publish_raw_image_, true);
        pnh_.param<bool>("publish_fan_image", publish_fan_image_, true);
        pnh_.param<int>("fan_image_width", fan_image_width_, 700);
        pnh_.param<int>("fan_image_height", fan_image_height_, 700);
        pnh_.param<double>("fan_margin", fan_margin_, 20.0);
        pnh_.param<int>("fan_point_radius", fan_point_radius_, 1);

        raw_image_pub_ = it_.advertise("/bluerov/sonar/image_raw", 1);
        fan_image_pub_ = it_.advertise("/bluerov/sonar/fan_image_raw", 1);

        camera_info_pub_ = nh_.advertise<sensor_msgs::CameraInfo>("/bluerov/sonar/camera_info", 1);
        range_pub_ = nh_.advertise<std_msgs::Float32>("/bluerov/sonar/range_m", 1);
        status_pub_ = nh_.advertise<std_msgs::String>("/bluerov/sonar/status", 10, true);
        control_echo_pub_ = nh_.advertise<std_msgs::String>("/bluerov/sonar/control_echo", 10, true);

        control_sub_ = nh_.subscribe("/bluerov/sonar/control", 10, &BlueROVSonarNode::controlCallback, this);

        sonar_ = new ForwardlookingSonarSDK(this);

        applyCurrentConfig();

        connect(sonar_, &ForwardlookingSonarSDK::WarningText,
                this, &BlueROVSonarNode::onWarningText);

        connect(sonar_, &ForwardlookingSonarSDK::NewSonarDetected,
                this, &BlueROVSonarNode::onNewSonarDetected);

        connect(sonar_, &ForwardlookingSonarSDK::OutputData,
                this, &BlueROVSonarNode::onOutputData);

        connect_timer_ = new QTimer(this);
        connect(connect_timer_, &QTimer::timeout,
                this, &BlueROVSonarNode::tryConnect);
        connect_timer_->start(connect_retry_ms_);

        status_timer_ = new QTimer(this);
        connect(status_timer_, &QTimer::timeout,
                this, &BlueROVSonarNode::publishHeartbeat);
        status_timer_->start(1000);

        ros_timer_ = new QTimer(this);
        connect(ros_timer_, &QTimer::timeout,
                this, &BlueROVSonarNode::spinRosOnce);
        ros_timer_->start(10);

        publishStatus("sonar_ros_node_started");
        ROS_INFO("BlueROV sonar SDK ROS node started.");
        ROS_INFO("Raw sonar image topic: /bluerov/sonar/image_raw");
        ROS_INFO("Fan sonar image topic: /bluerov/sonar/fan_image_raw");
        ROS_INFO("Sonar control topic: /bluerov/sonar/control");
    }

    ~BlueROVSonarNode()
    {
        if (sonar_) {
            sonar_->Disconnect();
        }
    }

private:
    void applyCurrentConfig()
    {
        if (use_low_freq_) {
            sonar_->SetLowFreq();
        } else {
            sonar_->SetHighFreq();
        }

        sonar_->SetRange(range_m_);
        sonar_->SetGain(gain_);
        sonar_->SetGainAssist(gain_assist_);

        if (use_fresh_water_) {
            sonar_->SetWatertype(freshWater);
        } else {
            sonar_->SetWatertype(saltWater);
        }

        if (speed_of_sound_ > 0.0) {
            sonar_->SetSpeedofSound(speed_of_sound_);
        }
    }

    std::string configString() const
    {
        std::ostringstream oss;
        oss << "range_m=" << range_m_
            << " | gain=" << gain_
            << " | freq=" << (use_low_freq_ ? "low" : "high")
            << " | water=" << (use_fresh_water_ ? "fresh" : "salt")
            << " | gain_assist=" << (gain_assist_ ? "true" : "false")
            << " | speed_of_sound=" << speed_of_sound_;
        return oss.str();
    }

    void tryConnect()
    {
        const QMap<uint32_t, BHSonarStatusMsg>& list = sonar_->GetSonarList();

        if (list.count() <= 0) {
            return;
        }

        if (!sonar_seen_reported_) {
            std::ostringstream oss;
            oss << "sonar_detected | sonar_count=" << list.count();

            for (auto it = list.constBegin(); it != list.constEnd(); ++it) {
                const BHSonarStatusMsg& s = it.value();
                oss << " | ip=" << ipToString(s.ipAddr).toStdString()
                    << " | deviceId=" << s.deviceId
                    << " | partNumber=" << s.partNumber;
            }

            publishStatus(oss.str());
            sonar_seen_reported_ = true;
        }

        if (auto_connect_ && !connected_flag_) {
            ROS_INFO("Sonar detected and auto_connect=true. Calling Connect().");
            sonar_->Connect();
            applyCurrentConfig();

            connected_flag_ = true;
            publishStatus("connect_called | " + configString());
        }
    }

    void onNewSonarDetected()
    {
        publishStatus("NewSonarDetected");
        tryConnect();
    }

    void onWarningText(QString txt)
    {
        publishStatus(std::string("sdk_warning | ") + txt.toStdString());
    }

    void onOutputData(ulong size, OUTDATA* data, double range, int height, int width)
    {
        if (data == nullptr || size == 0 || height <= 0 || width <= 0) {
            publishStatus("invalid_output_data");
            return;
        }

        frame_count_++;
        last_range_m_ = range;
        last_width_ = width;
        last_height_ = height;
        last_output_time_ = ros::Time::now();

        ros::Time stamp = ros::Time::now();

        if (publish_raw_image_) {
            publishRawImage(data, size, range, height, width, stamp);
        }

        if (publish_fan_image_) {
            publishFanImage(data, size, range, height, width, stamp);
        }

        std_msgs::Float32 range_msg;
        range_msg.data = static_cast<float>(range);
        range_pub_.publish(range_msg);

        if (frame_count_ % 20 == 0) {
            std::ostringstream oss;
            oss << "OutputData"
                << " | frame=" << frame_count_
                << " | size=" << size
                << " | range_m=" << range
                << " | height=" << height
                << " | width=" << width
                << " | first_value=" << static_cast<int>(data[0].value)
                << " | " << configString();
            publishStatus(oss.str());
        }
    }

    void publishRawImage(OUTDATA* data,
                         ulong size,
                         double range,
                         int height,
                         int width,
                         const ros::Time& stamp)
    {
        const size_t expected_size = static_cast<size_t>(height) * static_cast<size_t>(width);
        const size_t copy_size = std::min(static_cast<size_t>(size), expected_size);

        std::vector<uint8_t> image_data(expected_size, 0);

        for (size_t i = 0; i < copy_size; ++i) {
            int v = static_cast<int>(data[i].value);
            v = std::max(0, std::min(255, v));
            image_data[i] = static_cast<uint8_t>(v);
        }

        sensor_msgs::Image img;
        img.header.stamp = stamp;
        img.header.frame_id = frame_id_;
        img.height = static_cast<uint32_t>(height);
        img.width = static_cast<uint32_t>(width);
        img.encoding = "mono8";
        img.is_bigendian = false;
        img.step = static_cast<uint32_t>(width);
        img.data = image_data;

        raw_image_pub_.publish(img);

        sensor_msgs::CameraInfo info;
        info.header = img.header;
        info.height = img.height;
        info.width = img.width;
        camera_info_pub_.publish(info);
    }

    void publishFanImage(OUTDATA* data,
                         ulong size,
                         double max_range_m,
                         int raw_height,
                         int raw_width,
                         const ros::Time& stamp)
    {
        if (data == nullptr || size == 0 || max_range_m <= 0.0 || raw_height <= 0 || raw_width <= 0) {
            return;
        }

        const int W = fan_image_width_;
        const int H = fan_image_height_;
        if (W <= 0 || H <= 0) {
            return;
        }

        const size_t total = std::min(
            static_cast<size_t>(size),
            static_cast<size_t>(raw_height) * static_cast<size_t>(raw_width)
        );
        if (total == 0) {
            return;
        }

        // Use the bearing extent reported by the SDK to fit the complete sector
        // into the output canvas while keeping the same pixel scale on both axes.
        double min_angle_deg = std::numeric_limits<double>::infinity();
        double max_angle_deg = -std::numeric_limits<double>::infinity();
        for (size_t i = 0; i < total; ++i) {
            const double angle = static_cast<double>(data[i].angle);
            if (std::isfinite(angle)) {
                min_angle_deg = std::min(min_angle_deg, angle);
                max_angle_deg = std::max(max_angle_deg, angle);
            }
        }
        if (!std::isfinite(min_angle_deg) || !std::isfinite(max_angle_deg) ||
            max_angle_deg <= min_angle_deg) {
            return;
        }

        const double min_angle = min_angle_deg * M_PI / 180.0;
        const double max_angle = max_angle_deg * M_PI / 180.0;
        double min_lateral_factor = std::min({0.0, std::sin(min_angle), std::sin(max_angle)});
        double max_lateral_factor = std::max({0.0, std::sin(min_angle), std::sin(max_angle)});
        if (min_angle <= -(M_PI / 2.0) && max_angle >= -(M_PI / 2.0)) {
            min_lateral_factor = -1.0;
        }
        if (min_angle <= (M_PI / 2.0) && max_angle >= (M_PI / 2.0)) {
            max_lateral_factor = 1.0;
        }
        double max_forward_factor = std::max(std::cos(min_angle), std::cos(max_angle));
        if (min_angle <= 0.0 && max_angle >= 0.0) {
            max_forward_factor = 1.0;
        }
        if (max_forward_factor <= 0.0) {
            return;
        }

        const double margin = std::max(1.0, std::min(fan_margin_, std::min(W, H) / 2.0 - 1.0));
        const double lateral_span = max_range_m * (max_lateral_factor - min_lateral_factor);
        const double forward_span = max_range_m * max_forward_factor;
        if (lateral_span <= 0.0 || forward_span <= 0.0 ||
            W <= 2.0 * margin || H <= 2.0 * margin) {
            return;
        }
        const double scale = std::min((W - 2.0 * margin) / lateral_span,
                                      (H - 2.0 * margin) / forward_span);
        const double cx = margin - scale * max_range_m * min_lateral_factor;
        const double cy = H - margin;

        std::vector<uint8_t> fan_img(static_cast<size_t>(W) * static_cast<size_t>(H), 0);
        const double min_angle_rad = min_angle_deg * M_PI / 180.0;
        const double max_angle_rad = max_angle_deg * M_PI / 180.0;

        for (size_t i = 0; i < total; ++i) {
            double r = static_cast<double>(data[i].range);
            const double angle_deg = static_cast<double>(data[i].angle);
            if (!std::isfinite(angle_deg)) {
                continue;
            }
            int value = static_cast<int>(data[i].value);
            value = std::max(0, std::min(255, value));

            // If the SDK range is invalid, use the raw image row as a linear range bin.
            if (!std::isfinite(r) || r < 0.0 || r > max_range_m * 1.2) {
                const size_t row = i / static_cast<size_t>(raw_width);
                r = max_range_m * static_cast<double>(row) /
                    static_cast<double>(std::max(raw_height - 1, 1));
            }
            if (r < 0.0 || r > max_range_m) {
                continue;
            }

            const double angle_rad = angle_deg * M_PI / 180.0;
            if (angle_rad < min_angle_rad || angle_rad > max_angle_rad) {
                continue;
            }
            const double x = r * std::sin(angle_rad);
            const double y = r * std::cos(angle_rad);
            const int px = static_cast<int>(std::round(cx + x * scale));
            const int py = static_cast<int>(std::round(cy - y * scale));

            // Increase the splat radius with range so adjacent beams do not leave
            // dark radial gaps. fan_point_radius_ remains the minimum footprint.
            const size_t column = i % static_cast<size_t>(raw_width);
            double angle_step_deg = 0.0;
            if (column + 1 < static_cast<size_t>(raw_width) && i + 1 < total &&
                std::isfinite(static_cast<double>(data[i + 1].angle))) {
                angle_step_deg = std::abs(static_cast<double>(data[i + 1].angle) - angle_deg);
            } else if (column > 0 && i > 0 &&
                       std::isfinite(static_cast<double>(data[i - 1].angle))) {
                angle_step_deg = std::abs(angle_deg - static_cast<double>(data[i - 1].angle));
            }
            const double beam_spacing_px = r * scale * angle_step_deg * M_PI / 180.0;
            const int adaptive_radius = static_cast<int>(std::ceil(beam_spacing_px * 0.5));
            const int radius = std::max(fan_point_radius_, std::min(adaptive_radius, 8));
            const int radius_sq = radius * radius;
            for (int dy = -radius; dy <= radius; ++dy) {
                for (int dx = -radius; dx <= radius; ++dx) {
                    if (dx * dx + dy * dy > radius_sq) {
                        continue;
                    }
                    const int xx = px + dx;
                    const int yy = py + dy;
                    if (xx < 0 || xx >= W || yy < 0 || yy >= H) {
                        continue;
                    }
                    const size_t idx = static_cast<size_t>(yy) * static_cast<size_t>(W) +
                                       static_cast<size_t>(xx);
                    if (value > fan_img[idx]) {
                        fan_img[idx] = static_cast<uint8_t>(value);
                    }
                }
            }
        }

        sensor_msgs::Image fan_msg;
        fan_msg.header.stamp = stamp;
        fan_msg.header.frame_id = frame_id_;
        fan_msg.height = static_cast<uint32_t>(H);
        fan_msg.width = static_cast<uint32_t>(W);
        fan_msg.encoding = "mono8";
        fan_msg.is_bigendian = false;
        fan_msg.step = static_cast<uint32_t>(W);
        fan_msg.data = fan_img;
        fan_image_pub_.publish(fan_msg);
    }

    void controlCallback(const std_msgs::String::ConstPtr& msg)
    {
        const std::string cmd = trimLower(msg->data);

        std_msgs::String echo;
        echo.data = "received_control | " + cmd;
        control_echo_pub_.publish(echo);

        if (cmd == "connect" || cmd == "start") {
            auto_connect_ = true;
            sonar_->Connect();
            applyCurrentConfig();
            connected_flag_ = true;
            publishStatus("manual_start_connect_called | " + configString());
            return;
        }

        if (cmd == "disconnect" || cmd == "stop") {
            auto_connect_ = false;
            sonar_->Disconnect();
            connected_flag_ = false;
            publishStatus("manual_stop_disconnect_called");
            return;
        }

        if (cmd == "low" || cmd == "freq low") {
            use_low_freq_ = true;
            sonar_->SetLowFreq();
            publishStatus("set_low_freq | " + configString());
            return;
        }

        if (cmd == "high" || cmd == "freq high") {
            use_low_freq_ = false;
            sonar_->SetHighFreq();
            publishStatus("set_high_freq | " + configString());
            return;
        }

        if (cmd == "fresh" || cmd == "water fresh") {
            use_fresh_water_ = true;
            sonar_->SetWatertype(freshWater);
            publishStatus("set_fresh_water | " + configString());
            return;
        }

        if (cmd == "salt" || cmd == "water salt") {
            use_fresh_water_ = false;
            sonar_->SetWatertype(saltWater);
            publishStatus("set_salt_water | " + configString());
            return;
        }

        if (cmd == "gain_assist on") {
            gain_assist_ = true;
            sonar_->SetGainAssist(true);
            publishStatus("set_gain_assist_on | " + configString());
            return;
        }

        if (cmd == "gain_assist off") {
            gain_assist_ = false;
            sonar_->SetGainAssist(false);
            publishStatus("set_gain_assist_off | " + configString());
            return;
        }

        if (cmd == "status" || cmd == "params") {
            publishStatus("manual_status | " + configString());
            return;
        }

        if (cmd.rfind("range ", 0) == 0) {
            double r = std::atof(cmd.substr(6).c_str());
            if (r > 0.0) {
                range_m_ = r;
                sonar_->SetRange(range_m_);

                std::ostringstream oss;
                oss << "set_range | " << range_m_ << " | " << configString();
                publishStatus(oss.str());
            } else {
                publishStatus("invalid_range_command | " + cmd);
            }
            return;
        }

        if (cmd.rfind("gain ", 0) == 0) {
            int g = std::atoi(cmd.substr(5).c_str());
            g = std::max(0, std::min(100, g));
            gain_ = g;
            sonar_->SetGain(gain_);

            std::ostringstream oss;
            oss << "set_gain | " << gain_ << " | " << configString();
            publishStatus(oss.str());
            return;
        }

        if (cmd.rfind("speed ", 0) == 0) {
            double s = std::atof(cmd.substr(6).c_str());
            if (s > 0.0) {
                speed_of_sound_ = s;
                sonar_->SetSpeedofSound(speed_of_sound_);

                std::ostringstream oss;
                oss << "set_speed_of_sound | " << speed_of_sound_ << " | " << configString();
                publishStatus(oss.str());
            } else {
                publishStatus("invalid_speed_command | " + cmd);
            }
            return;
        }

        publishStatus("unknown_control | " + cmd);
    }

    void publishHeartbeat()
    {
        const QMap<uint32_t, BHSonarStatusMsg>& list = sonar_->GetSonarList();

        std::ostringstream oss;
        oss << "heartbeat"
            << " | sonar_count=" << list.count()
            << " | auto_connect=" << (auto_connect_ ? "true" : "false")
            << " | connected_flag=" << (connected_flag_ ? "true" : "false")
            << " | frames=" << frame_count_
            << " | last_range_m=" << last_range_m_
            << " | last_width=" << last_width_
            << " | last_height=" << last_height_
            << " | " << configString();

        publishStatus(oss.str());
    }

    void publishStatus(const std::string& text)
    {
        std_msgs::String msg;
        msg.data = text;
        status_pub_.publish(msg);
    }

    void spinRosOnce()
    {
        ros::spinOnce();

        if (!ros::ok()) {
            if (sonar_) {
                sonar_->Disconnect();
            }
            QCoreApplication::quit();
        }
    }

private:
    ros::NodeHandle nh_;
    ros::NodeHandle pnh_;
    image_transport::ImageTransport it_;

    image_transport::Publisher raw_image_pub_;
    image_transport::Publisher fan_image_pub_;
    ros::Publisher camera_info_pub_;
    ros::Publisher range_pub_;
    ros::Publisher status_pub_;
    ros::Publisher control_echo_pub_;
    ros::Subscriber control_sub_;

    ForwardlookingSonarSDK* sonar_ = nullptr;

    QTimer* connect_timer_ = nullptr;
    QTimer* status_timer_ = nullptr;
    QTimer* ros_timer_ = nullptr;

    std::string frame_id_;

    double range_m_ = 10.0;
    int gain_ = 50;
    bool use_low_freq_ = true;
    bool use_fresh_water_ = true;
    bool gain_assist_ = false;
    double speed_of_sound_ = 1500.0;

    bool auto_connect_ = true;
    int connect_retry_ms_ = 3000;

    bool publish_raw_image_ = true;
    bool publish_fan_image_ = true;
    int fan_image_width_ = 1240;
    int fan_image_height_ = 700;
    double fan_margin_ = 20.0;
    int fan_point_radius_ = 1;

    bool connected_flag_ = false;
    bool sonar_seen_reported_ = false;

    uint64_t frame_count_ = 0;
    double last_range_m_ = 0.0;
    int last_width_ = 0;
    int last_height_ = 0;
    ros::Time last_output_time_;
};

int main(int argc, char** argv)
{
    ros::init(argc, argv, "bluerov_sonar_sdk_node");

    QCoreApplication app(argc, argv);

    ros::NodeHandle nh;
    ros::NodeHandle pnh("~");

    BlueROVSonarNode node(nh, pnh);

    return app.exec();
}
