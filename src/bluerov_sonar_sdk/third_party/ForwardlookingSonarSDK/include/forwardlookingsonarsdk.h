#ifndef FORWARDLOOKINGSONARSDK_H
#define FORWARDLOOKINGSONARSDK_H

#include <QObject>
#include <QMutex>
#include <QMap>
#include <QTimer>
#include <QDateTime>
#include "ForwardlookingSonarSDK_global.h"
#include "bhsonar.h"

class SonarWidget;
class Sonarsurface;
class ClientCtrl;
class OsStatusRx;
class Logger;
class Player;
class BufferEntry;
class OutputBuffer;

class FORWARDLOOKINGSONARSDK_EXPORT ForwardlookingSonarSDK : public QObject
{
    Q_OBJECT
public:
    ForwardlookingSonarSDK(QObject *parent = nullptr);
    ~ForwardlookingSonarSDK();
    ////直接使用声呐
    // 获取声呐列表
    const QMap<uint32_t, BHSonarStatusMsg>& GetSonarList();
    // 连接声呐
    void Connect();
    // 断开连接
    void Disconnect();
    // 设置高频工作模式
    void SetHighFreq();
    // 设置低频工作模式
    void SetLowFreq();
    // 设置量程
    void SetRange(double rng);
    // 设置增益
    void SetGain(double gn);
    // 设置辅助增益
    void SetGainAssist(bool sign);
    // 设置水环境类型
    void SetWatertype(int type);
    // 设置水中声速
    void SetSpeedofSound(double speed);
    ////回放数据
    // 打开文件
    bool OpenFileEx(QString fileName);
    // 开始回放
    void StartReplay();
    // 停止回放
    void StopReplay();
    // 播放下一帧
    void PlayNext();
    ////记录数据
    // 开始记录
    void StartLog();
    // 停止记录
    void StopLog();
    // 设置记录文件大小
    void SetMaxLogSize(uint32_t size);
    // 设置记录默认目录
    void SetLogDirectory(QString logDir);
private:
    // 更新声纳信息
    void UpdateSonarInfo(BHSonarPartNumberType pn);
    // 设置声呐信息
    void SetSonarInfo(BHSonarStatusMsg msg);
    // 发送简单指令信号
    void FireSonar();
    // 设置显示模式
    void SetDisplayMode(eDisplayMode displayMode);
    // 更新日志名称
    void UpdateLogFileName();
    // 放弃重连
    void AbortReconnect();
private:
    BHSonarPartNumberType m_partNumber;

    QMap<uint32_t, BHSonarStatusMsg>     m_sonarList;
    QMap<uint32_t, QDateTime>            m_statusMessageTimes;
    QMutex                               m_statusMessageTimesLock;
    QMutex                               m_sonarLock;
    //---------------------------对象----------------------------------------
//    SonarWidget    *fanDisplay;             // 雷达图显示窗口
//    Sonarsurface   *pSonarSurface;          // 声纳图
    ClientCtrl     *sonarClient;            // 网络客户端控制
    OsStatusRx     *sonarStatus;            // UDP状态, 接收声呐UDP广播包
    Logger         *logger;                 // 数据记录对象
    Player         *player;                 // 数据回放对象

    // Replay position data
    QString       m_replayFile;       // Name of the current file for replay
    quint64*      m_pEntries;         // File position entry table for the current reply file
    int           m_nEntries;         // Number of oculus entries found in the replay file
    int           m_index;            // Current entry index
    int			  m_indexLower;
    int			  m_indexUpper;		  // Upper entry index
    BufferEntry*   m_entry;            // The last read oculus message
    QTimer        m_replay;           // The replay timer
    QDateTime     m_payloadDateTime;
    int			  m_playSpeed;

    bool          m_useRawSonar;

    QTimer        timerMoniter;     // 监控网络上的声呐包

    bool	       m_timeout;

    int      demandMode;                    // 发送给声纳的模式命令:1(750kHz)、2(1.2MHz)
    int      demandGain;                    // 发送给声纳的增益命令:0-100(%)
    double   demandRange;                   // 发送给声纳的量程命令

    WaterType waterType;                    // 环境水质类型
    double   speedOfSound;                  // 环境声速
    double   salinity;                      // 环境盐度值

    bool     gainAssist;                    // 辅助增益
    uint8_t  gammaCorrection;               // gamma调节:0-255
    uint8_t  netSpeedLimit;                 // 最大网速:10-100

    // 当前声呐信息
    BHSonarInfo		*m_pSonarInfo;
    // 显示模式
    eDisplayMode m_displayMode;
    // 输出变换用临时变量
    OutputBuffer * outBuffer;

signals:
    void NewSonarDetected();

    void SonarClientStateChanged();

    void WarningText(QString str);

    // 更新扇形图像缓存
    void UpdateFan(double rng, int nBrgs, short* pBrgs, bool updateProjection = false);
    // 根据新数据更新图像
    void UpdateImg(int nRngs, int nBrgs, uchar* pData);
    //
    void UpdateWidget();
    // 输出数据
    void OutputData(ulong size, OUTDATA * data, double range, int height, int width);

private slots:
    void onNewPayload(unsigned short type, unsigned short version, double time, unsigned payloadSize, quint8* pPayload);
    // 响应从UDP Socket获取的声纳状态信息
    void NewStatusMsg(BHSonarStatusMsg osm, quint16 valid, quint16 invalid);

    void ConnectionFailed(QString error);

    // 获取声纳传来的信息
    void NewReturnFire(BufferEntry* pEntry);

    // Client连接超时
    void SocketTimeout();
    // Client重连
    void SocketReconnecting();
    // 断开Client连接
    void SocketDisconnected();
    // 监视器等待可用的声纳
    void MonitorAvailableSonars();

};

#endif // FORWARDLOOKINGSONARSDK_H
