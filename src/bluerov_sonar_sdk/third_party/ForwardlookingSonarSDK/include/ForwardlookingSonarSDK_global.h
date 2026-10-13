#ifndef FORWARDLOOKINGSONARSDK_GLOBAL_H
#define FORWARDLOOKINGSONARSDK_GLOBAL_H

#include <QtCore/qglobal.h>

#if defined(FORWARDLOOKINGSONARSDK_LIBRARY)
#  define FORWARDLOOKINGSONARSDK_EXPORT Q_DECL_EXPORT
#else
#  define FORWARDLOOKINGSONARSDK_EXPORT Q_DECL_IMPORT
#endif

// 输出数据结构
// 枚举不同显示模式
enum eDisplayMode : int
{
    offline,
    online,
    review
};
// 枚举不同声纳模式
enum SonarMode : int
{
  navigation = 1,        // 750kHz
  identification = 2,    // 1.2MHz
};

// 枚举不同水环境类型
enum WaterType : int
{
  freshWater,
  saltWater,
  fixedValue
};

typedef struct tagOutData{
    double range;
    double angle;
    uchar value;
}OUTDATA;

#endif // FORWARDLOOKINGSONARSDK_GLOBAL_H
