#ifndef OUTPUTBUFFER_H
#define OUTPUTBUFFER_H
#include "ForwardlookingSonarSDK_global.h"

class OutputBuffer
{
public:
    OutputBuffer();
    ~OutputBuffer();

    // Methods
    void AddRawFanImg(double rng, int nRngs, int nBrgs, short* pBrgs, uchar *pData);
    OUTDATA * pData;    // 数据
    ulong size;         // 数据长度
private:
    // 数据
    double Range;       // 量程
    int nRanges;        // 量程点数
    int nBrgs;          // 角度点数
};

#endif // OUTPUTBUFFER_H
