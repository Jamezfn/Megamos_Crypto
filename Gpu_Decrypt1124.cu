// #define __CUDACC__

#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>
#include <mutex>
#include <functional>
#include <semaphore.h>
#include <malloc.h>
#include <string>
#include <unistd.h>
#include <sys/time.h>

////windows 下修正
//#include"Windows.h"
//#include <stdio.h>
//#include <time.h>

#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <cooperative_groups.h>

using namespace cooperative_groups;
using namespace std;
#define _CRT_SECURE_NO_WARNINGS


struct timeval start, end_time;






const uint8_t SubCpuThreadCount = 1;
const uint16_t FileCount = 0x1550;//0xaa8;
struct InitGH{ uint32_t g40; uint32_t g48; uint16_t h40; uint16_t h48; };
struct InitLMR { uint8_t l40; uint8_t m40; uint8_t r40; uint8_t l48; uint8_t m48; uint8_t r48; };
struct CommonHeadIndexStr { uint32_t ThCount; uint32_t ThOffSetIndex;  uint32_t TlmrCount; uint32_t TlmrOffSetIndex; };

const uint32_t G_TCBInitghLen = 0xe800000;
const uint32_t G_TCBInitlmrLen = 0x280000;
const uint32_t G_TCBHLen = 0x10000;
struct G_TableCommonBlock{ InitGH ThInitgh[G_TCBInitghLen]; InitLMR TlmrInitlmr[G_TCBInitlmrLen]; CommonHeadIndexStr Tchis[G_TCBHLen]; };
struct G_TableCommonBlock_Dev{ InitGH ThInitgh[2][G_TCBInitghLen]; InitLMR TlmrInitlmr[2][G_TCBInitlmrLen]; CommonHeadIndexStr Tchis[G_TCBHLen]; };
struct G_TableCommonBlockSet { G_TableCommonBlock G_TCB[SubCpuThreadCount]; };
struct G_TableCommonBlockSet* Local_G_TCBS = (struct G_TableCommonBlockSet*)malloc(sizeof(struct G_TableCommonBlockSet));

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * 读写文件操作  * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */
bool ReadTCBH_OP(CommonHeadIndexStr* Buf_TCBHis, uint16_t DstTCBHisID, string sTComHead){
	memset(Buf_TCBHis, 0, G_TCBHLen * sizeof(CommonHeadIndexStr));

	uint16_t DirIndex = DstTCBHisID / 0x10;
    uint8_t FileIndex = DstTCBHisID % 0x10;
    //string sTmp = sTComHead + to_string(DirIndex) + "/" + to_string(FileIndex) + "_ComHead.bin";
   	// string sTmp = "../6_ComHead.bin";
	//string sTmp = "/mnt/sd/Tlmr/255/CommonHead/0/0_ComHead.bin";
	string sTmp = "/mnt/sd1/Tlmr/255/CommonHead/x_ComHead.bin";
	const char* DstTCBHisPath = sTmp.c_str();
	uint32_t TCBHiCountTmp = 0;

    FILE* TCBH_fr = fopen(DstTCBHisPath, "rb");
    if (TCBH_fr == NULL)
    {
        return false;
    }

    int skResult = fseek(TCBH_fr, 0, SEEK_END);
	if (skResult != 0)
	{
		fclose(TCBH_fr);
        return false;
	}

    uint32_t Len = ftell(TCBH_fr);
    TCBHiCountTmp = Len / sizeof(CommonHeadIndexStr);

    skResult = fseek(TCBH_fr, 0, SEEK_SET);
	if (skResult != 0)
	{
		fclose(TCBH_fr);
        return false;
	}
	
	if (TCBHiCountTmp != G_TCBHLen)
	{
		fclose(TCBH_fr);
        return false;
	}

    uint32_t readbytelen = fread(Buf_TCBHis, sizeof(CommonHeadIndexStr), TCBHiCountTmp, TCBH_fr);
	if (readbytelen != TCBHiCountTmp)
	{
		fclose(TCBH_fr);
        return false;
	}
	
    fclose(TCBH_fr);
    return true;
}
bool ReadTlmr_OP(InitLMR* Buf_Initlmr, uint32_t Buf_TlmrIndexCount, uint16_t DstTlmrID, string sTlmrData){
	memset(Buf_Initlmr, 0, G_TCBInitlmrLen * sizeof(InitLMR));

	uint16_t DirIndex = DstTlmrID / 0x10;
    uint8_t FileIndex = DstTlmrID % 0x10;
    //string sTmp = sTlmrData + to_string(DirIndex) + "/" + to_string(FileIndex) + ".bin";

    //string sTmp = "/mnt/sd/Tlmr/255/Data/0/0.bin";
	// string sTmp = "../6_TlmrNew.bin";
	string sTmp = "/mnt/sd1/Tlmr/255/Data/x_Tlmr.bin";
	const char* DstTlmrPath = sTmp.c_str();
	uint32_t TlmrIndexCountTmp;

    FILE* Tlmr_fr = fopen(DstTlmrPath, "rb");
    if (Tlmr_fr == NULL)
    {
        return false;
    }

    int skResult = fseek(Tlmr_fr, 0, SEEK_END);
	if (skResult != 0)
	{
		fclose(Tlmr_fr);
        return false;
	}

    TlmrIndexCountTmp = ftell(Tlmr_fr);

    skResult = fseek(Tlmr_fr, 0, SEEK_SET);
	if (skResult != 0)
	{
		fclose(Tlmr_fr);
        return false;
	}

	if (TlmrIndexCountTmp != Buf_TlmrIndexCount)
	{
		fclose(Tlmr_fr);
        return false;
	}
	
    uint32_t readbytelen = fread(Buf_Initlmr, 1, TlmrIndexCountTmp, Tlmr_fr);
    if (readbytelen != TlmrIndexCountTmp)
	{
		fclose(Tlmr_fr);
        return false;
	}
	
    fclose(Tlmr_fr);
    return true;
}
bool ReadTh_OP(InitGH* Buf_Initgh, uint32_t Buf_ThIndexCount, uint16_t DstThID, string sThData){
	memset(Buf_Initgh, 0, G_TCBInitghLen * sizeof(InitGH));

	uint16_t DirIndex = DstThID / 0x10;
    uint8_t FileIndex = DstThID % 0x10;
    //string sTmp = sThData + to_string(DirIndex) + "/" + to_string(FileIndex) + ".bin";
    //string sTmp = "/mnt/nv1/Th/Data/0/0.bin";
	// string sTmp = "/mnt/nv1/6_ThNew.bin";
	string sTmp = "/mnt/nv1/Th/Data/x_Th.bin";
	const char* DstThPath = sTmp.c_str();
	uint32_t ThIndexCountTmp = 0;

    FILE* Th_fr = fopen(DstThPath, "rb");
    if (Th_fr == NULL)
    {
        return false;
    }

    int skResult = fseek(Th_fr, 0, SEEK_END);
	if (skResult != 0)
	{
		fclose(Th_fr);
        return false;
	}

    ThIndexCountTmp = ftell(Th_fr);
    fseek(Th_fr, 0, SEEK_SET);
	skResult = fseek(Th_fr, 0, SEEK_SET);
	if (skResult != 0)
	{
		fclose(Th_fr);
        return false;
	}

	if (ThIndexCountTmp != Buf_ThIndexCount)
	{
		fclose(Th_fr);
        return false;
	}
	
    uint32_t readbytelen = fread(Buf_Initgh, 1, ThIndexCountTmp, Th_fr);
	if (readbytelen != ThIndexCountTmp)
	{
		fclose(Th_fr);
        return false;
	}
	
    if (fclose(Th_fr) != 0)
	{
		return false;
	}

    return true;
}


/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * Megamos算法流程的各个小操作定义 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */
__device__ uint8_t dev_Out7Bit[SubCpuThreadCount][7];
__device__ uint64_t dev_nC0[SubCpuThreadCount];
__device__ uint8_t dev_aCT0[SubCpuThreadCount][33];
__device__ uint64_t dev_nC1[SubCpuThreadCount];
__device__ uint8_t dev_aCT1[SubCpuThreadCount][48];
__device__ uint8_t dev_BiuKey[SubCpuThreadCount][13];


#define kernelthread 0x80
#define kernelblock 0x200
#define BiuBufLen 0x4000

struct BiuState{ 
	uint32_t key7Byte_H[BiuBufLen]; uint32_t key7Byte_L[BiuBufLen]; 
	uint32_t key[BiuBufLen]; uint32_t g[BiuBufLen]; 
	uint16_t h[BiuBufLen]; uint8_t l[BiuBufLen]; 
	uint8_t m[BiuBufLen]; uint8_t r[BiuBufLen]; 
};
struct BiuParaNode{
	uint32_t SpCount[kernelblock]; uint32_t BiuCount[kernelblock]; uint32_t MidCount[kernelblock]; 
	BiuState Bs_Pre[kernelblock]; BiuState Bs_New[kernelblock]; BiuState Bs_Mid[kernelblock]; BiuState Bs_Sp[kernelblock]; 
};
struct BiuParaNode* Local_BPN = (struct BiuParaNode*)malloc(sizeof(struct BiuParaNode));


__device__ void PreSucThird(BiuState* __restrict__ BS_In, BiuState* __restrict__ BS_Sp, uint32_t* __restrict__ BiuCount, uint32_t* __restrict__ SpCount, const uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t g, h, l, m, r, a, b, c, key, key7Byte_H, key7Byte_L;
	uint32_t idyIn, idyOut;
	__shared__ uint32_t checkCount_In, checkCount_Out;
	checkCount_In = *BiuCount;
	checkCount_Out = *SpCount;
	__syncthreads();
	//48
	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x) 
	{
		g = BS_In->g[idyIn];
		h = BS_In->h[idyIn];
		l = BS_In->l[idyIn];
		m = BS_In->m[idyIn];
		r = BS_In->r[idyIn];
		key = BS_In->key[idyIn];
		key7Byte_H = BS_In->key7Byte_H[idyIn];
		key7Byte_L = BS_In->key7Byte_L[idyIn];	

		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//ki = NLFSR_v2(a, b, c, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				b = para_T0 & 1;
			}
		}
		
		if (b == dev_Out7Bit[Tid][6])
		{
			idyOut = atomicAdd(&checkCount_Out, 1);
			BS_Sp->key7Byte_H[idyOut] = key7Byte_H;
			BS_Sp->key7Byte_L[idyOut] = key7Byte_L;
			BS_Sp->key[idyOut] = key;
		}
	}
	__syncthreads();
	*SpCount = checkCount_Out;
	__syncthreads();
}
__device__ void PreSucSecond(BiuState* __restrict__ BS_In, BiuState* __restrict__ BS_Out, uint32_t* __restrict__ BiuCount, const uint8_t Index, const uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t g, h, l, m, r, a, b, c, key, key7Byte_H, key7Byte_L;
	uint32_t idyIn, idyOut;
	__shared__ uint32_t checkCount_In, checkCount_Out;
	checkCount_In = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();
	//41-47
	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x) 
	{
		g = BS_In->g[idyIn];
		h = BS_In->h[idyIn];
		l = BS_In->l[idyIn];
		m = BS_In->m[idyIn];
		r = BS_In->r[idyIn];
		key = BS_In->key[idyIn];
		key7Byte_H = BS_In->key7Byte_H[idyIn];
		key7Byte_L = BS_In->key7Byte_L[idyIn];	

		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//ki = NLFSR_v2(a, b, c, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				b = para_T0 & 1;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}

		if (b == dev_Out7Bit[Tid][Index])
		{
			idyOut = atomicAdd(&checkCount_Out, 1);
			BS_Out->g[idyOut] = g;
			BS_Out->h[idyOut] = h;
			BS_Out->l[idyOut] = l;
			BS_Out->m[idyOut] = m;
			BS_Out->r[idyOut] = r;
			BS_Out->key7Byte_H[idyOut] = key7Byte_H;
			BS_Out->key7Byte_L[idyOut] = key7Byte_L;
			BS_Out->key[idyOut] = key;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}
__device__ void PreSucFirst(const InitGH* __restrict__ IGH, const InitLMR* __restrict__ ILMR,  
				BiuState* __restrict__ BS_Out, uint32_t* __restrict__ BiuCount, uint32_t TlmrCount, uint32_t Offset, const uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t g, h, l, m, r, a, b, c, key, key7Byte_H, key7Byte_L;
	uint32_t idyIn, idyOut;
	__shared__ uint32_t checkCount_In, checkCount_Out;
	checkCount_In = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();
	//40
	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x) 
	{
		para_T0 = idyIn + Offset;
		para_Q_H = para_T0 / TlmrCount;
		para_Q_L = para_T0 % TlmrCount;

		key7Byte_H = IGH[para_Q_H].g40;
		key7Byte_L = IGH[para_Q_H].h40;
		a = ILMR[para_Q_L].l40 << 16;
		b = ILMR[para_Q_L].m40 << 8;
		c = a | b;
		key = c | ILMR[para_Q_L].r40;

		g = IGH[para_Q_H].g48;
		h = IGH[para_Q_H].h48;
		l = ILMR[para_Q_L].l48;
		m = ILMR[para_Q_L].m48;
		r = ILMR[para_Q_L].r48;
	/*
		g = IGH[para_Q_H].g40;
		h = IGH[para_Q_H].h40;
		l = ILMR[para_Q_L].l40;
		m = ILMR[para_Q_L].m40;
		r = ILMR[para_Q_L].r40;
		key7Byte_H = g;
		key7Byte_L = h;
		a = l << 16;
		b = m << 8;
		c = a | b;
		key = c | r;
		//40
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		//41
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		//42
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		//43
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		//44
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		//45
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		//46
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		//47
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
	*/
		//48
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//ki = NLFSR_v2(a, b, c, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				b = para_T0 & 1;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}

		if (b == dev_Out7Bit[Tid][0])
		{
			idyOut = atomicAdd(&checkCount_Out, 1);
			BS_Out->g[idyOut] = g;
			BS_Out->h[idyOut] = h;
			BS_Out->l[idyOut] = l;
			BS_Out->m[idyOut] = m;
			BS_Out->r[idyOut] = r;
			BS_Out->key7Byte_H[idyOut] = key7Byte_H;
			BS_Out->key7Byte_L[idyOut] = key7Byte_L;
			BS_Out->key[idyOut] = key;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}
__device__ void PreSort(const InitGH* __restrict__ IGH, const InitLMR* __restrict__ ILMR, const CommonHeadIndexStr* __restrict__ CHIS, 
				BiuState* __restrict__ BS_In, BiuState* __restrict__ BS_Out, BiuState* __restrict__ BS_Sp, 
				uint32_t* __restrict__ BiuCount, uint32_t* __restrict__ SpCount, const uint8_t Tid)
{
	uint32_t AllCount, LastCount, ThOffset, TlmrOffset, i;
	*SpCount = 0;

	//0
	AllCount = CHIS[0].TlmrCount * CHIS[0].ThCount;
	LastCount = AllCount % BiuBufLen;
	AllCount -= LastCount;
	for (i = 0; i < AllCount; i+=BiuBufLen) 
	{
		*BiuCount = BiuBufLen;
		PreSucFirst(IGH, ILMR, BS_In, BiuCount, CHIS[0].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	if (LastCount != 0)
	{
		*BiuCount = LastCount;
		PreSucFirst(IGH, ILMR, BS_In, BiuCount, CHIS[0].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	//1
	AllCount = CHIS[1].TlmrCount * CHIS[1].ThCount;
	ThOffset = CHIS[0].ThCount;
	TlmrOffset = CHIS[0].TlmrCount;
	LastCount = AllCount % BiuBufLen;
	AllCount -= LastCount;
	for (i = 0; i < AllCount; i+=BiuBufLen) 
	{
		*BiuCount = BiuBufLen;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[1].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	if (LastCount != 0)
	{
		*BiuCount = LastCount;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[1].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	//2
	AllCount = CHIS[2].TlmrCount * CHIS[2].ThCount;
	ThOffset += CHIS[1].ThCount;
	TlmrOffset += CHIS[1].TlmrCount;
	LastCount = AllCount % BiuBufLen;
	AllCount -= LastCount;
	for (i = 0; i < AllCount; i+=BiuBufLen) 
	{
		*BiuCount = BiuBufLen;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[2].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	if (LastCount != 0)
	{
		*BiuCount = LastCount;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[2].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	//3
	AllCount = CHIS[3].TlmrCount * CHIS[3].ThCount;
	ThOffset += CHIS[2].ThCount;
	TlmrOffset += CHIS[2].TlmrCount;
	LastCount = AllCount % BiuBufLen;
	AllCount -= LastCount;
	for (i = 0; i < AllCount; i+=BiuBufLen) 
	{
		*BiuCount = BiuBufLen;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[3].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	if (LastCount != 0)
	{
		*BiuCount = LastCount;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[3].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	//4
	AllCount = CHIS[4].TlmrCount * CHIS[4].ThCount;
	ThOffset += CHIS[3].ThCount;
	TlmrOffset += CHIS[3].TlmrCount;
	LastCount = AllCount % BiuBufLen;
	AllCount -= LastCount;
	for (i = 0; i < AllCount; i+=BiuBufLen) 
	{
		*BiuCount = BiuBufLen;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[4].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	if (LastCount != 0)
	{
		*BiuCount = LastCount;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[4].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	//5
	AllCount = CHIS[5].TlmrCount * CHIS[5].ThCount;
	ThOffset += CHIS[4].ThCount;
	TlmrOffset += CHIS[4].TlmrCount;
	LastCount = AllCount % BiuBufLen;
	AllCount -= LastCount;
	for (i = 0; i < AllCount; i+=BiuBufLen) 
	{
		*BiuCount = BiuBufLen;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[5].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	if (LastCount != 0)
	{
		*BiuCount = LastCount;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[5].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	//6
	AllCount = CHIS[6].TlmrCount * CHIS[6].ThCount;
	ThOffset += CHIS[5].ThCount;
	TlmrOffset += CHIS[5].TlmrCount;
	LastCount = AllCount % BiuBufLen;
	AllCount -= LastCount;
	for (i = 0; i < AllCount; i+=BiuBufLen) 
	{
		*BiuCount = BiuBufLen;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[6].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	if (LastCount != 0)
	{
		*BiuCount = LastCount;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[6].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	//7
	AllCount = CHIS[7].TlmrCount * CHIS[7].ThCount;
	ThOffset += CHIS[6].ThCount;
	TlmrOffset += CHIS[6].TlmrCount;
	LastCount = AllCount % BiuBufLen;
	AllCount -= LastCount;
	for (i = 0; i < AllCount; i+=BiuBufLen) 
	{
		*BiuCount = BiuBufLen;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[7].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	if (LastCount != 0)
	{
		*BiuCount = LastCount;
		PreSucFirst(&IGH[ThOffset], &ILMR[TlmrOffset], BS_In, BiuCount, CHIS[7].TlmrCount, i, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 1, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 2, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 3, Tid);
		PreSucSecond(BS_Out, BS_In, BiuCount, 4, Tid);
		PreSucSecond(BS_In, BS_Out, BiuCount, 5, Tid);
		PreSucThird(BS_Out, BS_Sp, BiuCount, SpCount, Tid);
	}
	
}


__device__ void RevSucFirst(BiuState* __restrict__ Bs_Sp, BiuState* __restrict__ Bs_Out, 
				uint32_t* __restrict__ BiuCount, const uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t g, h, l, m, r, a, b, c, key, key7Byte_H, key7Byte_L, idyIn, idyOut;
	__shared__ uint32_t checkCount_In, checkCount_Out;
	checkCount_In = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();

	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x){
		g = Bs_Sp->key7Byte_H[idyIn];
		h = Bs_Sp->key7Byte_L[idyIn];
		key = Bs_Sp->key[idyIn];
		l = key >> 16;
		m = (key >> 8) & 0xff;
		r = key & 0xff;
		// if (g == 0x5e6e6b && h == 0x588 && l == 0x7d && m == 0x5c && r == 0x5)
		// {
		// 	uint8_t jfla = 1;
		// }

		//h = H_1(h);
		{
			para_Q_H = h >> 10;
			para_Q_L = h >> 3;
			para_T0 = para_Q_H & para_Q_L;
			para_Q_H = h >> 2;
			para_Q_H &= h;
			para_Q_L = para_T0 ^ para_Q_H;
			para_T0 = h >> 12;
			para_Q_H = ~para_T0;
			para_T0 = para_Q_H ^ para_Q_L;
			para_Q_L = para_T0 & 1;
			para_Q_H = h << 1;
			para_T0 = para_Q_H | para_Q_L;
			h = para_T0 & 0x1fff;
		}
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 0; g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 0;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
			//a = NLFSR(a_Pre, b_Pre, c_Pre, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				a = para_T0 & 1;
			}
		}
		c = a ^ dev_aCT0[Tid][0];	//!(NLFSR(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth])
		para_Q_L = ~c;	
		para_Q_H = ~m;	//!(b ^ m6)
		para_T0 = para_Q_H & para_Q_L;	//b = !(b ^ m6) & !(NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth]);
		b = para_T0 & 1;
		if (b == 1)
		{
			idyOut = atomicAdd(&checkCount_Out, 2);
			Bs_Out->key[idyOut] = 0;
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			idyOut += 1;
			Bs_Out->key[idyOut] = 1;
			Bs_Out->g[idyOut] = g ^ 0x80000;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
		}

		g = Bs_Sp->key7Byte_H[idyIn];
		l = key >> 16;
		m = (key >> 8) & 0xff;
		r = key & 0xff;
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 1;	g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 1;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
			//a = NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				a = para_T0 & 1;
			}
		}
		c = a ^ dev_aCT0[Tid][0];	//!(NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth]);
		para_Q_L = ~c;
		b = m ^ 1;	//!(b ^ m6)
		para_Q_H = ~b;
		para_T0 = para_Q_H & para_Q_L;	//b = !(b ^ m6) & !(NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth]);
		b = para_T0 & 1;
		if (b == 1)
		{
			idyOut = atomicAdd(&checkCount_Out, 2);
			Bs_Out->key[idyOut] = 0;
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			idyOut += 1;
			Bs_Out->key[idyOut] = 1;
			Bs_Out->g[idyOut] = g ^ 0x80000;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}
__device__ void RevSucSecond(BiuState* __restrict__ Bs_In, BiuState* __restrict__ Bs_Out, 
				uint32_t* __restrict__ BiuCount, const uint8_t Tid, const uint32_t Depth)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t g, h, l, m, r, a, b, c, key, idyIn, idyOut;
	__shared__ uint32_t checkCount_In, checkCount_Out;
	checkCount_In = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();

	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x){
		g = Bs_In->g[idyIn];
		h = Bs_In->h[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		key = Bs_In->key[idyIn];
		key <<= 1;

		//h = H_1(h);
		{
			para_Q_H = h >> 10;
			para_Q_L = h >> 3;
			para_T0 = para_Q_H & para_Q_L;
			para_Q_H = h >> 2;
			para_Q_H &= h;
			para_Q_L = para_T0 ^ para_Q_H;
			para_T0 = h >> 12;
			para_Q_H = ~para_T0;
			para_T0 = para_Q_H ^ para_Q_L;
			para_Q_L = para_T0 & 1;
			para_Q_H = h << 1;
			para_T0 = para_Q_H | para_Q_L;
			h = para_T0 & 0x1fff;
		}
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 0; g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 0;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
			//a = NLFSR(a_Pre, b_Pre, c_Pre, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				a = para_T0 & 1;
			}
		}
		c = a ^ dev_aCT0[Tid][Depth];	//!(NLFSR(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth])
		para_Q_L = ~c;	
		para_Q_H = ~m;	//!(b ^ m6)
		para_T0 = para_Q_H & para_Q_L;	//b = !(b ^ m6) & !(NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth]);
		b = para_T0 & 1;
		if (b == 1)
		{
			idyOut = atomicAdd(&checkCount_Out, 2);
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			idyOut += 1;
			Bs_Out->key[idyOut] = key | 1;
			Bs_Out->g[idyOut] = g ^ 0x80000;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
		}

		g = Bs_In->g[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 1;	g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 1;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
			//a = NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				a = para_T0 & 1;
			}
		}
		c = a ^ dev_aCT0[Tid][Depth];	//!(NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth]);
		para_Q_L = ~c;
		b = m ^ 1;	//!(b ^ m6)
		para_Q_H = ~b;
		para_T0 = para_Q_H & para_Q_L;	//b = !(b ^ m6) & !(NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth]);
		b = para_T0 & 1;
		if (b == 1)
		{
			idyOut = atomicAdd(&checkCount_Out, 2);
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			idyOut += 1;
			Bs_Out->key[idyOut] = key | 1;
			Bs_Out->g[idyOut] = g ^ 0x80000;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}
__device__ void RevSucThird(BiuState* __restrict__ Bs_In, BiuState* __restrict__ Bs_Sp, 
				uint32_t* __restrict__ BiuCount, const uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t g, h, l, m, r, a, b, c, key, idyIn, idysp;
	__shared__ uint32_t checkCount_In, checkCount_Sp;
	checkCount_In = *BiuCount;
	checkCount_Sp = 0;
	__syncthreads();

	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x){	
		g = Bs_In->g[idyIn];
		h = Bs_In->h[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		key = Bs_In->key[idyIn];

		//h = H_1(h);
		{
			para_Q_H = h >> 10;
			para_Q_L = h >> 3;
			para_T0 = para_Q_H & para_Q_L;
			para_Q_H = h >> 2;
			para_Q_H &= h;
			para_Q_L = para_T0 ^ para_Q_H;
			para_T0 = h >> 12;
			para_Q_H = ~para_T0;
			para_T0 = para_Q_H ^ para_Q_L;
			para_Q_L = para_T0 & 1;
			para_Q_H = h << 1;
			para_T0 = para_Q_H | para_Q_L;
			h = para_T0 & 0x1fff;
		}
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 0; g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 0;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
			//a = NLFSR(a_Pre, b_Pre, c_Pre, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				a = para_T0 & 1;
			}
		}
		c = a ^ dev_aCT0[Tid][32];	//!(NLFSR(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth])
		para_Q_L = ~c;	
		para_Q_H = ~m;	//!(b ^ m6)
		para_T0 = para_Q_H & para_Q_L;	//b = !(b ^ m6) & !(NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth]);
		b = para_T0 & 1;
		if (b == 1)
		{
			idysp = atomicAdd(&checkCount_Sp, 2);
			Bs_Sp->key7Byte_L[idysp] = 0;
			Bs_Sp->key[idysp] = key;
			Bs_Sp->g[idysp] = g;
			Bs_Sp->h[idysp] = h;
			Bs_Sp->l[idysp] = l;
			Bs_Sp->m[idysp] = m;
			Bs_Sp->r[idysp] = r;
			idysp += 1;
			Bs_Sp->key7Byte_L[idysp] = 1;
			Bs_Sp->key[idysp] = key;
			Bs_Sp->g[idysp] = g ^ 0x80000;
			Bs_Sp->h[idysp] = h;
			Bs_Sp->l[idysp] = l;
			Bs_Sp->m[idysp] = m;
			Bs_Sp->r[idysp] = r;
		}

		g = Bs_In->g[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 1;	g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 1;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
			//a = NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				a = para_T0 & 1;
			}
		}
		c = a ^ dev_aCT0[Tid][32];	//!(NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth]);
		para_Q_L = ~c;
		b = m ^ 1;	//!(b ^ m6)
		para_Q_H = ~b;
		para_T0 = para_Q_H & para_Q_L;	//b = !(b ^ m6) & !(NLFSR_v2(a_Pre, b_Pre, c_Pre, l, m, r) ^ dev_aCT0[Tid][Depth]);
		b = para_T0 & 1;
		if (b == 1)
		{
			idysp = atomicAdd(&checkCount_Sp, 2);
			Bs_Sp->key7Byte_L[idysp] = 0;
			Bs_Sp->key[idysp] = key;
			Bs_Sp->g[idysp] = g;
			Bs_Sp->h[idysp] = h;
			Bs_Sp->l[idysp] = l;
			Bs_Sp->m[idysp] = m;
			Bs_Sp->r[idysp] = r;
			idysp += 1;
			Bs_Sp->key7Byte_L[idysp] = 1;
			Bs_Sp->key[idysp] = key;
			Bs_Sp->g[idysp] = g ^ 0x80000;
			Bs_Sp->h[idysp] = h;
			Bs_Sp->l[idysp] = l;
			Bs_Sp->m[idysp] = m;
			Bs_Sp->r[idysp] = r;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Sp;
	__syncthreads();
}
__device__ void RevSucSpFirst(BiuState* __restrict__ Bs_Sp, BiuState* __restrict__ Bs_Out, 
				uint32_t* __restrict__ BiuCount, uint32_t Offset, const uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t g, h, l, m, r, a, b, c, key, kb, idysp, idyOut;
	__shared__ uint32_t checkCount_Sp, checkCount_Out;
	checkCount_Sp = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();
	
	for (idysp = threadIdx.x; idysp < checkCount_Sp; idysp += blockDim.x)
	{
		Offset += idysp;
		g = Bs_Sp->g[Offset];
		h = Bs_Sp->h[Offset];
		l = Bs_Sp->l[Offset];
		m = Bs_Sp->m[Offset];
		r = Bs_Sp->r[Offset];
		key = Bs_Sp->key[Offset];
		kb = Bs_Sp->key7Byte_L[Offset];
		kb <<= 1;

		//h = H_1(h);
		{
			para_Q_H = h >> 10;
			para_Q_L = h >> 3;
			para_T0 = para_Q_H & para_Q_L;
			para_Q_H = h >> 2;
			para_Q_H &= h;
			para_Q_L = para_T0 ^ para_Q_H;
			para_T0 = h >> 12;
			para_Q_H = ~para_T0;
			para_T0 = para_Q_H ^ para_Q_L;
			para_Q_L = para_T0 & 1;
			para_Q_H = h << 1;
			para_T0 = para_Q_H | para_Q_L;
			h = para_T0 & 0x1fff;
		}
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 0; g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 0;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
		}
		para_T0 = ~m;	//!(b ^ m6)
		b = para_T0 & 1;
		if (b == 1)
		{
			idyOut = atomicAdd(&checkCount_Out, 2);
			Bs_Out->key7Byte_L[idyOut] = kb;
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			idyOut += 1;
			Bs_Out->key7Byte_L[idyOut] = kb | 1;
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g ^ 0x80000;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
		}

		g = Bs_Sp->g[Offset];
		l = Bs_Sp->l[Offset];
		m = Bs_Sp->m[Offset];
		r = Bs_Sp->r[Offset];
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 1;	g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 1;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
		}
		b = m ^ 1;	//!(b ^ m6)
		para_T0 = ~b;
		b = para_T0 & 1;
		if (b == 1)
		{
			idyOut = atomicAdd(&checkCount_Out, 2);
			Bs_Out->key7Byte_L[idyOut] = kb;
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			idyOut += 1;
			Bs_Out->key7Byte_L[idyOut] = kb | 1;
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g ^ 0x80000;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}
__device__ void RevSucSpSecond(BiuState* __restrict__ Bs_In, BiuState* __restrict__ Bs_Out, uint32_t* __restrict__ BiuCount, const uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t g, h, l, m, r, a, b, c, key, kb, idyIn, idyOut;
	__shared__ uint32_t checkCount_In, checkCount_Out;
	checkCount_In = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();

	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x)
	{
		g = Bs_In->g[idyIn];
		h = Bs_In->h[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		key = Bs_In->key[idyIn];
		kb = Bs_In->key7Byte_L[idyIn];
		kb <<= 1;

		//h = H_1(h);
		{
			para_Q_H = h >> 10;
			para_Q_L = h >> 3;
			para_T0 = para_Q_H & para_Q_L;
			para_Q_H = h >> 2;
			para_Q_H &= h;
			para_Q_L = para_T0 ^ para_Q_H;
			para_T0 = h >> 12;
			para_Q_H = ~para_T0;
			para_T0 = para_Q_H ^ para_Q_L;
			para_Q_L = para_T0 & 1;
			para_Q_H = h << 1;
			para_T0 = para_Q_H | para_Q_L;
			h = para_T0 & 0x1fff;
		}
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 0; g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 0;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
		}
		para_T0 = ~m;	//!(b ^ m6)
		b = para_T0 & 1;
		if (b == 1)
		{
			idyOut = atomicAdd(&checkCount_Out, 2);
			Bs_Out->key7Byte_L[idyOut] = kb;
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			idyOut += 1;
			Bs_Out->key7Byte_L[idyOut] = kb | 1;
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g ^ 0x80000;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
		}

		g = Bs_In->g[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		///////////calc
		{
			//m6 = ((l >> 4) & 1) ^ 1;	g = G_1(g, h, m6);
			{
				para_Q_H = l >> 4;
				para_T0 = para_Q_H ^ 1;
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g >> 22;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 & 1;
				para_T0 = 0x100000 - para_Q_L;
				para_Q_H = para_T0 & 0xb0240;
				para_T0 = g ^ para_Q_H;
				para_Q_H = para_T0 << 1;
				para_T0 = para_Q_H | para_Q_L;
				g = para_T0 & 0x7fffff;
			}
			//a = (fm(g, h) ^ b_Pre ^ (l >> 2) ^ (l >> 5)) & 1;
			{
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				a = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				a &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_T0 = l >> 2;
				para_Q_H = l >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = m >> 6;
				para_Q_H = a ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				a = para_T0 & 1;
			}
			//b = (fr(g, h) ^ c_Pre ^ (m >> 2) ^ (m >> 5)) & 1;
			{
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				b = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				b &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = m >> 2;
				para_Q_H = m >> 5;
				para_Q_L = para_T0 ^ para_Q_H;
				para_T0 = r >> 6;
				para_Q_H = b ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = (fl(g, h) ^ a_Pre ^ (r >> 3) ^ g) & 1;
			{
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				c = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				c &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_Q_L = r >> 3;
				para_Q_H = para_Q_L ^ g;
				para_T0 = l >> 6;
				para_Q_L = c ^ para_T0;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//l = ((l << 1) | a) & 0x7f; //m = ((m << 1) | b) & 0x7f; //r = ((r << 1) | c) & 0x7f;
			{
				para_Q_H = l << 1;
				l = para_Q_H | a;
				para_T0 = l >> 7;
				a = para_T0 & 1;
				l &= 0x7f;
				para_Q_H = m << 1;
				m = para_Q_H | b;
				para_T0 = m >> 7;
				b = para_T0 & 1;
				m &= 0x7f;
				para_Q_H = r << 1;
				r = para_Q_H | c;
				para_T0 = r >> 7;
				c = para_T0 & 1;
				r &= 0x7f;
			}
		}
		b = m ^ 1;	//!(b ^ m6)
		para_T0 = ~b;
		b = para_T0 & 1;
		if (b == 1)
		{
			idyOut = atomicAdd(&checkCount_Out, 2);
			Bs_Out->key7Byte_L[idyOut] = kb;
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			idyOut += 1;
			Bs_Out->key7Byte_L[idyOut] = kb | 1;
			Bs_Out->key[idyOut] = key;
			Bs_Out->g[idyOut] = g ^ 0x80000;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}

__device__ void RevCheckInit(BiuState* __restrict__ Bs_In, BiuState* __restrict__ Bs_Out, uint32_t* __restrict__ BiuCount, uint8_t Tid)
{
	uint64_t para_Q, para_P;
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t g, h, l, m, r, a, b, c, key, kb, Key7Byte_H, Key7Byte_L, idyIn, idyOut;
	__shared__ uint32_t checkCount_In, checkCount_Out;
	checkCount_In = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();
	
	//0-7
	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x)
	{
		g = Bs_In->g[idyIn];
		h = Bs_In->h[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		key = Bs_In->key[idyIn];
		kb = Bs_In->key7Byte_L[idyIn];

		/////////////////////////////Init_1->Init
		//_Init
		{
			//19-13: l
			{
				a = g >> 22;
				para_T0 = l >> 6;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 19;
				para_Q_H = c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = l >> 5;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 18;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = l >> 4;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 17;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = l >> 3;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 16;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = l >> 2;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 15;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = l >> 1;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 14;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				b = l & 1;
				para_T0 = a ^ b;
				c = para_T0 << 13;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;
			}
			//12-6: m
			{
				a = g >> 22;
				para_T0 = m >> 6;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 12;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = m >> 5;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 11;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = m >> 4;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 10;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = m >> 3;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 9;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = m >> 2;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 8;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = m >> 1;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 7;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				b = m & 1;
				para_T0 = a ^ b;
				c = para_T0 << 6;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;
			}
			//5-0: r
			{
				a = g >> 22;
				para_T0 = r >> 6;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 5;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = r >> 5;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 4;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = r >> 4;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 3;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = r >> 3;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 2;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = r >> 2;
				b = para_T0 & 1;
				para_T0 = a ^ b;
				c = para_T0 << 1;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g >> 22;
				para_T0 = r >> 1;
				b = para_T0 & 1;
				c = a ^ b;
				para_Q_H += c;
				para_T0 = 0x100000 - b;
				a = para_T0 & 0xb0240;
				c = g ^ a;
				para_T0 = c << 1;
				a = para_T0 | b;
				g = a & 0x7fffff;

				a = g << 1;
				b = r & 1;
				g = a | b;
				a = para_Q_H & 0xff;
				b = a << 24;
				para_Q_L = b | g;
				a = para_Q_H >> 8;
				b = h << 12;
				para_Q_H = b | a;
			}
		}
		//_Q
		{
			//para_Q_H
			{
				//m6 = (((para_Q_H >> 21) ^ (para_Q_H >> 15)) & 1) << 11;
				a = para_Q_H >> 21;
				b = para_Q_H >> 15;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 11;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 20) ^ (para_Q_H >> 14)) & 1) << 10;
				a = para_Q_H >> 20;
				b = para_Q_H >> 14;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 10;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 19) ^ (para_Q_H >> 13)) & 1) << 9;
				a = para_Q_H >> 19;
				b = para_Q_H >> 13;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 9;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 18) ^ (para_Q_H >> 12)) & 1) << 8;
				a = para_Q_H >> 18;
				b = para_Q_H >> 12;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 8;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 17) ^ (para_Q_H >> 11)) & 1) << 7;
				a = para_Q_H >> 17;
				b = para_Q_H >> 11;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 7;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 16) ^ (para_Q_H >> 10)) & 1) << 6;
				a = para_Q_H >> 16;
				b = para_Q_H >> 10;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 6;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 15) ^ (para_Q_H >> 9)) & 1) << 5;
				a = para_Q_H >> 15;
				b = para_Q_H >> 9;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 5;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 14) ^ (para_Q_H >> 8)) & 1) << 4;
				a = para_Q_H >> 14;
				b = para_Q_H >> 8;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 4;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 13) ^ (para_Q_H >> 7)) & 1) << 3;
				a = para_Q_H >> 13;
				b = para_Q_H >> 7;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 3;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 12) ^ (para_Q_H >> 6)) & 1) << 2;
				a = para_Q_H >> 12;
				b = para_Q_H >> 6;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 2;
				para_Q_H ^= c;
				//m6 = (((para_Q_H >> 11) ^ (para_Q_H >> 5)) & 1) << 1;
				a = para_Q_H >> 11;
				b = para_Q_H >> 5;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 1;
				para_Q_H ^= c;
				//m6 = ((para_Q_H >> 10) ^ (para_Q_H >> 4)) & 1;
				a = para_Q_H >> 10;
				b = para_Q_H >> 4;
				c = a ^ b;
				c = c & 1;
				para_Q_H ^= c;
			}
			//para_Q_L
			{
				//m6 = (((para_Q_H >> 9) ^ (para_Q_H >> 3)) & 1) << 31;
				a = para_Q_H >> 9;
				b = para_Q_H >> 3;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 31;
				para_Q_L ^= c;
				//m6 = (((para_Q_H >> 8) ^ (para_Q_H >> 2)) & 1) << 30;
				a = para_Q_H >> 8;
				b = para_Q_H >> 2;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 30;
				para_Q_L ^= c;
				//m6 = (((para_Q_H >> 7) ^ (para_Q_H >> 1)) & 1) << 29;
				a = para_Q_H >> 7;
				b = para_Q_H >> 1;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 29;
				para_Q_L ^= c;
				//m6 = (((para_Q_H >> 6) ^ para_Q_H) & 1) << 28;
				a = para_Q_H >> 6;
				c = a ^ para_Q_H;
				para_T0 = c & 1;
				c = para_T0 << 28;
				para_Q_L ^= c;
				//m6 = (((para_Q_H >> 5) ^ (para_Q_L >> 31)) & 1) << 27;
				a = para_Q_H >> 5;
				b = para_Q_L >> 31;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 27;
				para_Q_L ^= c;
				//m6 = (((para_Q_H >> 4) ^ (para_Q_L >> 30)) & 1) << 26;
				a = para_Q_H >> 4;
				b = para_Q_L >> 30;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 26;
				para_Q_L ^= c;
				//m6 = (((para_Q_H >> 3) ^ (para_Q_L >> 29)) & 1) << 25;
				a = para_Q_H >> 3;
				b = para_Q_L >> 29;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 25;
				para_Q_L ^= c;
				//m6 = (((para_Q_H >> 2) ^ (para_Q_L >> 28)) & 1) << 24;
				a = para_Q_H >> 2;
				b = para_Q_L >> 28;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 24;
				para_Q_L ^= c;
				//m6 = (((para_Q_H >> 1) ^ (para_Q_L >> 27)) & 1) << 23;
				a = para_Q_H >> 1;
				b = para_Q_L >> 27;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 23;
				para_Q_L ^= c;
				//m6 = ((para_Q_H ^ (para_Q_L >> 26)) & 1) << 22;
				b = para_Q_L >> 26;
				c = para_Q_H ^ b;
				para_T0 = c & 1;
				c = para_T0 << 22;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 31) ^ (para_Q_L >> 25)) & 1) << 21;
				a = para_Q_L >> 31;
				b = para_Q_L >> 25;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 21;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 30) ^ (para_Q_L >> 24)) & 1) << 20;
				a = para_Q_L >> 30;
				b = para_Q_L >> 24;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 20;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 29) ^ (para_Q_L >> 23)) & 1) << 19;
				a = para_Q_L >> 29;
				b = para_Q_L >> 23;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 19;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 28) ^ (para_Q_L >> 22)) & 1) << 18;
				a = para_Q_L >> 28;
				b = para_Q_L >> 22;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 18;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 27) ^ (para_Q_L >> 21)) & 1) << 17;
				a = para_Q_L >> 27;
				b = para_Q_L >> 21;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 17;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 26) ^ (para_Q_L >> 20)) & 1) << 16;
				a = para_Q_L >> 26;
				b = para_Q_L >> 20;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 16;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 25) ^ (para_Q_L >> 19)) & 1) << 15;
				a = para_Q_L >> 25;
				b = para_Q_L >> 19;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 15;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 24) ^ (para_Q_L >> 18)) & 1) << 14;
				a = para_Q_L >> 24;
				b = para_Q_L >> 18;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 14;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 23) ^ (para_Q_L >> 17)) & 1) << 13;
				a = para_Q_L >> 23;
				b = para_Q_L >> 17;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 13;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 22) ^ (para_Q_L >> 16)) & 1) << 12;
				a = para_Q_L >> 22;
				b = para_Q_L >> 16;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 12;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 21) ^ (para_Q_L >> 15)) & 1) << 11;
				a = para_Q_L >> 21;
				b = para_Q_L >> 15;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 11;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 20) ^ (para_Q_L >> 14)) & 1) << 10;
				a = para_Q_L >> 20;
				b = para_Q_L >> 14;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 10;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 19) ^ (para_Q_L >> 13)) & 1) << 9;
				a = para_Q_L >> 19;
				b = para_Q_L >> 13;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 9;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 18) ^ (para_Q_L >> 12)) & 1) << 8;
				a = para_Q_L >> 18;
				b = para_Q_L >> 12;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 8;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 17) ^ (para_Q_L >> 11)) & 1) << 7;
				a = para_Q_L >> 17;
				b = para_Q_L >> 11;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 7;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 16) ^ (para_Q_L >> 10)) & 1) << 6;
				a = para_Q_L >> 16;
				b = para_Q_L >> 10;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 6;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 15) ^ (para_Q_L >> 9)) & 1) << 5;
				a = para_Q_L >> 15;
				b = para_Q_L >> 9;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 5;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 14) ^ (para_Q_L >> 8)) & 1) << 4;
				a = para_Q_L >> 14;
				b = para_Q_L >> 8;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 4;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 13) ^ (para_Q_L >> 7)) & 1) << 3;
				a = para_Q_L >> 13;
				b = para_Q_L >> 7;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 3;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 12) ^ (para_Q_L >> 6)) & 1) << 2;
				a = para_Q_L >> 12;
				b = para_Q_L >> 6;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 2;
				para_Q_L ^= c;
				//m6 = (((para_Q_L >> 11) ^ (para_Q_L >> 5)) & 1) << 1;
				a = para_Q_L >> 11;
				b = para_Q_L >> 5;
				c = a ^ b;
				para_T0 = c & 1;
				c = para_T0 << 1;
				para_Q_L ^= c;
				//m6 = ((para_Q_L >> 10) ^ (para_Q_L >> 4)) & 1;
				a = para_Q_L >> 10;
				b = para_Q_L >> 4;
				para_T0 = a ^ b;
				c = para_T0 & 1;
				para_Q_L ^= c;
			}
		}
		para_Q = para_Q_H;
		para_Q <<= 0x20;
		para_Q += para_Q_L;
		para_P = para_Q - dev_nC0[Tid];
		Key7Byte_L = para_P & 0xffffffff;
		Key7Byte_H = para_P >> 0x20;
		Key7Byte_H &= 0xffffff;
		para_Q = para_P + dev_nC1[Tid];
		para_Q_L = para_Q & 0xffffffff;
		para_Q_H = para_Q >> 0x20;
		para_Q_H &= 0xffffff;
		// Key7Byte_L = para_Q_L - dev_nC0_L[Tid];
		// para_T0 = Key7Byte_L > para_Q_L ? 1 : 0;
		// Key7Byte_H = para_Q_H - dev_nC0_H[Tid];
		// Key7Byte_H -= para_T0;
		// Key7Byte_H &= 0xffffff;
		// para_Q_L = Key7Byte_L + dev_nC1_L[Tid];
		// para_T0 = b < Key7Byte_L ? 1 : 0;
		// para_Q_H = Key7Byte_H + dev_nC1_H[Tid];
		// para_Q_H += para_T0;
		// para_Q_H &= 0xffffff;

		h = para_Q_H >> 12;
		para_T0 = kb << 0x18;
		Key7Byte_H |= para_T0;
		//Init:		g,l,m,r
		{
			a = para_Q_H & 0x3ff;
			b = a << 22;
			c = para_Q_L >> 10;
			a = b | c;
			para_T0 = para_Q_L ^ a;
			a = para_Q_H & 0xf;
			b = a << 28;
			c = para_Q_L >> 4;
			a = b | c;
			para_Q_L = para_T0 ^ a;

			a = para_Q_H >> 10;
			para_T0 = para_Q_H ^ a;
			a = para_Q_H >> 4;
			para_Q_H = para_T0 ^ a;

			r = para_Q_L & 1;
			a = para_Q_L >> 1;
			g = a & 0x7fffff;
				
			/////////////////0-5: r_New
			{
				a = para_Q_L >> 24;
				para_T0 = a & 0x3f;

				a = g & 1;
				c = a << 1;
				r |= c;
				c = para_T0 & 1;
				b = a ^ c;
				c = b << 23;
				g |= c;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 2;
				r |= c;
				c = para_T0 >> 1;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 3;
				r |= c;
				c = para_T0 >> 2;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 4;
				r |= c;
				c = para_T0 >> 3;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 5;
				r |= c;
				c = para_T0 >> 4;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 6;
				r |= c;
				c = para_T0 >> 5;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;
			}
			/////////////////6-12: m_New
			{
				a = para_Q_H & 0x1f;
				b = a << 2;
				c = para_Q_L >> 30;
				para_T0 = b | c;

				a = g & 1;
				m = a;
				c = para_T0 & 1;
				b = a ^ c;
				c = b << 23;
				g |= c;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 1;
				m |= c;
				c = para_T0 >> 1;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 2;
				m |= c;
				c = para_T0 >> 2;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 3;
				m |= c;
				c = para_T0 >> 3;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 4;
				m |= c;
				c = para_T0 >> 4;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 5;
				m |= c;
				c = para_T0 >> 5;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 6;
				m |= c;
				c = para_T0 >> 6;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;
			}
			/////////////////13-19: l_New
			{
				a = para_Q_H >> 5;
				para_T0 = a & 0x7f;

				a = g & 1;
				l = a;
				c = para_T0 & 1;
				b = a ^ c;
				c = b << 23;
				g |= c;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 1;
				l |= c;
				c = para_T0 >> 1;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 2;
				l |= c;
				c = para_T0 >> 2;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 3;
				l |= c;
				c = para_T0 >> 3;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 4;
				l |= c;
				c = para_T0 >> 4;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 5;
				l |= c;
				c = para_T0 >> 5;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;

				a = g & 1;
				c = a << 6;
				l |= c;
				c = para_T0 >> 6;
				b = c & 1;
				c = a ^ b;
				b = c << 23;
				g |= b;
				b = 0x200000 - a;
				c = b & 0x160480;
				a = g ^ c;
				g = a >> 1;
			}
		}
		
		/////////////////////////////0
		{
			//g ^= ((kb >> 0) & 1) << 19;
			{
				para_T0 = kb & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		/////////////////////////////1
		{
			//g ^= ((kb >> 1) & 1) << 19;
			{
				para_Q_L = kb >> 1;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		/////////////////////////////2
		{
			//g ^= ((kb >> 2) & 1) << 19;
			{
				para_Q_L = kb >> 2;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		/////////////////////////////3
		{
			//g ^= ((kb >> 3) & 1) << 19;
			{
				para_Q_L = kb >> 3;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		/////////////////////////////4
		{
			//g ^= ((kb >> 4) & 1) << 19;
			{
				para_Q_L = kb >> 4;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		/////////////////////////////5
		{
			//g ^= ((kb >> 5) & 1) << 19;
			{
				para_Q_L = kb >> 5;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		/////////////////////////////6
		{
			//g ^= ((kb >> 6) & 1) << 19;
			{
				para_Q_L = kb >> 6;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		/////////////////////////////7
		{
			//g ^= ((kb >> 7) & 1) << 19;
			{
				para_Q_L = kb >> 7;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//ki = NLFSR_v2(a, b, c, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				b = para_T0 & 1;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}

		if (b == dev_aCT1[Tid][0])
		{
			idyOut = atomicAdd(&checkCount_Out, 1);	
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			Bs_Out->key[idyOut] = key;
			Bs_Out->key7Byte_L[idyOut] = Key7Byte_L;
			Bs_Out->key7Byte_H[idyOut] = Key7Byte_H;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}
__device__ void RevCheckFirst(BiuState* __restrict__ Bs_In, BiuState* __restrict__ Bs_Out, uint32_t* __restrict__ BiuCount, uint8_t CheckIndex, uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t a, b, c, g, h, l, m, r, key, Key7Byte_H, Key7Byte_L, idyIn, idyOut;
	__shared__ uint32_t checkCount_Out, checkCount_In;
	checkCount_In = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();
	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x)
	{
		g = Bs_In->g[idyIn];
		h = Bs_In->h[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		key = Bs_In->key[idyIn];
		Key7Byte_H = Bs_In->key7Byte_H[idyIn];
		Key7Byte_L = Bs_In->key7Byte_L[idyIn];	 

		/////////calc
		{
			//g ^= ((key >> CheckIndex) & 1) << 19;
			{
				para_Q_L = key >> CheckIndex;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//ki = NLFSR_v2(a, b, c, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				b = para_T0 & 1;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		para_T0 = CheckIndex + 1;
		if (b == dev_aCT1[Tid][para_T0])
		{
			idyOut = atomicAdd(&checkCount_Out, 1);
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			Bs_Out->key[idyOut] = key;
			Bs_Out->key7Byte_L[idyOut] = Key7Byte_L;
			Bs_Out->key7Byte_H[idyOut] = Key7Byte_H;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}
__device__ void RevCheckFirstToMid(BiuState* __restrict__ Bs_In, BiuState* __restrict__ Bs_Mid, 
				uint32_t* __restrict__ BiuCount, uint32_t* __restrict__ MidCount, uint8_t CheckIndex, uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t a, b, c, g, h, l, m, r, key, Key7Byte_H, Key7Byte_L, idyIn, idymid;
	__shared__ uint32_t checkCount_Mid, checkCount_In;
	checkCount_In = *BiuCount;
	checkCount_Mid = *MidCount;
	__syncthreads();
	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x)
	{
		g = Bs_In->g[idyIn];
		h = Bs_In->h[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		key = Bs_In->key[idyIn];
		Key7Byte_H = Bs_In->key7Byte_H[idyIn];
		Key7Byte_L = Bs_In->key7Byte_L[idyIn];

		/////////calc
		{
			//g ^= ((key >> CheckIndex) & 1) << 19;
			{
				para_Q_L = key >> CheckIndex;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//ki = NLFSR_v2(a, b, c, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				b = para_T0 & 1;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		para_T0 = CheckIndex + 1;
		if (b == dev_aCT1[Tid][para_T0])
		{
			idymid = atomicAdd(&checkCount_Mid, 1);
			Bs_Mid->g[idymid] = g;
			Bs_Mid->h[idymid] = h;
			Bs_Mid->l[idymid] = l;
			Bs_Mid->m[idymid] = m;
			Bs_Mid->r[idymid] = r;
			Bs_Mid->key[idymid] = key;
			Bs_Mid->key7Byte_L[idymid] = Key7Byte_L;
			Bs_Mid->key7Byte_H[idymid] = Key7Byte_H;
		}
	}
	__syncthreads();
	*MidCount = checkCount_Mid;
	__syncthreads();
}
__device__ void RevCheckFirstFromMid(BiuState* __restrict__ Bs_Mid, BiuState* __restrict__ Bs_Out,   
				uint32_t* __restrict__ BiuCount, uint8_t CheckIndex, uint8_t Tid)
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t a, b, c, g, h, l, m, r, key, Key7Byte_H, Key7Byte_L, idymid, idyOut;
	__shared__ uint32_t checkCount_Out, checkCount_Mid;
	checkCount_Mid = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();
	
	for (idymid = threadIdx.x; idymid < checkCount_Mid; idymid += blockDim.x)
	{
		g = Bs_Mid->g[idymid];
		h = Bs_Mid->h[idymid];
		l = Bs_Mid->l[idymid];
		m = Bs_Mid->m[idymid];
		r = Bs_Mid->r[idymid];
		key = Bs_Mid->key[idymid];
		Key7Byte_H = Bs_Mid->key7Byte_H[idymid];
		Key7Byte_L = Bs_Mid->key7Byte_L[idymid];

		/////////calc
		{
			//g ^= ((key >> CheckIndex) & 1) << 19;
			{
				para_Q_L = key >> CheckIndex;
				para_T0 = para_Q_L & 1;
				para_Q_H = para_T0 << 19;
				g ^= para_Q_H;
			}
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//ki = NLFSR_v2(a, b, c, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				b = para_T0 & 1;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		para_T0 = CheckIndex + 1;
		if (b == dev_aCT1[Tid][para_T0])
		{
			idyOut = atomicAdd(&checkCount_Out, 1);
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			Bs_Out->key[idyOut] = key;
			Bs_Out->key7Byte_L[idyOut] = Key7Byte_L;
			Bs_Out->key7Byte_H[idyOut] = Key7Byte_H;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}
__device__ void RevCheckSecond(BiuState* __restrict__ Bs_In, BiuState* __restrict__ Bs_Out, uint32_t* __restrict__ BiuCount, uint8_t CheckIndex, uint8_t Tid) 
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t a, b, c, g, h, l, m, r, key, Key7Byte_H, Key7Byte_L, idyIn, idyOut;
	__shared__ uint32_t checkCount_Out, checkCount_In;
	checkCount_In = *BiuCount;
	checkCount_Out = 0;
	__syncthreads();
	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x)
	{
		g = Bs_In->g[idyIn];
		h = Bs_In->h[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		key = Bs_In->key[idyIn];
		Key7Byte_H = Bs_In->key7Byte_H[idyIn];
		Key7Byte_L = Bs_In->key7Byte_L[idyIn];
		
		/////////calc
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			//l = (a << 7) | l;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
				//l
				para_Q_H = a << 7;
				l |= para_Q_H;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			//m = (b << 7) | m;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
				//m
				para_Q_H = b << 7;
				m |= para_Q_H;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			//r = (c << 7) | r;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
				//r
				para_Q_H = c << 7;
				r |= para_Q_H;
			}
			//m6 = (l >> 5) ^ m;
			//g = G(g, h, m6);
			{
				//m6
				para_Q_H = l >> 5;
				para_T0 = para_Q_H ^ m;
				//g
				para_Q_L = para_T0 ^ h;
				para_Q_H = h >> 4;
				para_T0 = para_Q_H ^ para_Q_L;
				para_Q_H = h >> 10;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = g & 1;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_L = para_T0 << 23;
				para_T0 = g | para_Q_L;
				para_Q_L = 0x200000 - para_Q_H;
				para_Q_H = para_Q_L & 0x160480;
				g = para_T0 ^ para_Q_H;
				para_T0 = g >> 1;
				g = para_T0 & 0x7fffff;
			}
			//h = H(h);
			{
				para_Q_H = h >> 11;
				para_Q_L = h >> 4;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = h >> 3;
				para_Q_L = h >> 1;
				para_Q_H &= para_Q_L;
				para_Q_L = para_T0 ^ para_Q_H;
				para_Q_H = ~h;
				para_T0 = para_Q_L ^ para_Q_H;
				para_Q_H = para_T0 << 13;
				para_Q_L = h | para_Q_H;
				para_T0 = para_Q_L >> 1;
				h = para_T0 & 0x1fff;
			}
			//ki = NLFSR_v2(a, b, c, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				b = para_T0 & 1;
			}
			//final l,m,r
			l >>= 1;
			m >>= 1;
			r >>= 1;
		}
		if (b == dev_aCT1[Tid][CheckIndex])
		{
			idyOut = atomicAdd(&checkCount_Out, 1);
			Bs_Out->g[idyOut] = g;
			Bs_Out->h[idyOut] = h;
			Bs_Out->l[idyOut] = l;
			Bs_Out->m[idyOut] = m;
			Bs_Out->r[idyOut] = r;
			Bs_Out->key[idyOut] = key;
			Bs_Out->key7Byte_L[idyOut] = Key7Byte_L;
			Bs_Out->key7Byte_H[idyOut] = Key7Byte_H;
		}
	}
	__syncthreads();
	*BiuCount = checkCount_Out;
	__syncthreads();
}
__device__ void RevCheckEnd(BiuState* __restrict__ Bs_In, uint32_t* __restrict__ BiuCount, uint8_t Tid) 
{
	uint32_t para_Q_H, para_Q_L, para_T0;
	uint32_t a, b, c, g, h, l, m, r, key, Key7Byte_H, Key7Byte_L, idyIn;
	__shared__ uint32_t checkCount_In;
	checkCount_In = *BiuCount;
	__syncthreads();

	for (idyIn = threadIdx.x; idyIn < checkCount_In; idyIn += blockDim.x)
	{
		g = Bs_In->g[idyIn];
		h = Bs_In->h[idyIn];
		l = Bs_In->l[idyIn];
		m = Bs_In->m[idyIn];
		r = Bs_In->r[idyIn];
		key = Bs_In->key[idyIn];
		Key7Byte_H = Bs_In->key7Byte_H[idyIn];
		Key7Byte_L = Bs_In->key7Byte_L[idyIn];

		/////////calc
		{
			//a = (g ^ (r >> 4) ^ r ^ fl(g, h)) & 1;
			{
				//a
				para_Q_H = h >> 9;
				para_Q_L = g >> 18;
				a = para_Q_H & para_Q_L;
				para_Q_L = g >> 9;
				para_T0 = ~para_Q_L;
				a &= para_T0;
				para_Q_L = g >> 16;
				para_Q_H = ~para_Q_H;
				para_T0 = para_Q_H & para_Q_L;
				para_Q_H = g >> 4;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_Q_H = ~para_Q_H;
				para_T0 = g >> 18;
				para_T0 = ~para_T0;
				para_T0 &= para_Q_H;
				para_Q_H = g >> 22;
				para_T0 &= para_Q_H;
				a |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 9;
				para_T0 = para_Q_H & para_Q_L;
				a |= para_T0;
				para_Q_H = r >> 4;
				para_Q_L = para_Q_H ^ a;
				para_Q_H = g ^ r;
				para_T0 = para_Q_L ^ para_Q_H;
				a = para_T0 & 1;
			}
			//b = ((l >> 6) ^ (l >> 3) ^ l ^ fm(g, h)) & 1;
			{
				//b
				para_Q_H = h >> 5;
				para_Q_L = g >> 7;
				b = para_Q_H & para_Q_L;
				para_Q_H = g >> 17;
				para_T0 = ~para_Q_H;
				b &= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_H = g >> 21;
				para_Q_L = g >> 12;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = h >> 5;
				para_Q_H = ~para_Q_H;
				para_T0 &= para_Q_H;
				para_Q_H = h >> 12;
				para_T0 &= para_Q_H;
				b |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = g >> 17;
				para_T0 = para_Q_H & para_Q_L;
				b |= para_T0;
				para_T0 = l >> 6;
				para_Q_L = l >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = l ^ b;
				para_T0 = para_Q_H ^ para_Q_L;
				b = para_T0 & 1;
			}
			//c = ((m >> 6) ^ (m >> 3) ^ m ^ fr(g, h)) & 1;
			{
				//c
				para_Q_H = g >> 19;
				para_Q_L = g >> 8;
				c = para_Q_H & para_Q_L;
				para_T0 = h >> 11;
				para_T0 = ~para_T0;
				c &= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = g >> 20;
				para_Q_L = g >> 6;
				para_T0 &= para_Q_H;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_L;
				para_Q_L = g >> 8;
				para_Q_L = ~para_Q_L;
				para_T0 &= para_Q_L;
				para_Q_L = g >> 13;
				para_T0 &= para_Q_L;
				c |= para_T0;
				para_T0 = ~para_Q_H;
				para_Q_H = ~para_Q_L;
				para_Q_L = para_T0 & para_Q_H;
				para_Q_H = h >> 11;
				para_T0 = para_Q_H & para_Q_L;
				c |= para_T0;
				para_T0 = m >> 6;
				para_Q_L = m >> 3;
				para_Q_H = para_T0 ^ para_Q_L;
				para_Q_L = m ^ c;
				para_T0 = para_Q_H ^ para_Q_L;
				c = para_T0 & 1;
			}
			//ki = NLFSR_v2(a, b, c, l, m, r);
			{
				para_T0 = ~a;
				a = l >> 6;
				para_Q_L = ~a;
				para_Q_H = ~l;
				a = para_Q_H & para_Q_L;
				para_T0 |= a;
				a = ~b;
				para_Q_H = l >> 2;
				para_Q_L = ~para_Q_H;
				para_Q_H = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				a = ~c;
				c = r >> 3;
				para_Q_L = ~c;
				para_Q_H = m >> 3;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = para_Q_H & c;
				c = r >> 5;
				a = ~c;
				a |= b;
				para_T0 += a;
				c = ~para_Q_H;
				b = para_Q_L & c;
				c = m >> 1;
				a = ~c;
				a |= b;
				para_T0 += a;
				para_Q_H = m >> 6;
				a = ~para_Q_H;
				para_Q_H = l >> 2;
				para_Q_L = m >> 5;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 1;
				a = ~b;
				b = ~para_Q_H;
				c = ~para_Q_L;
				b &= c;
				a |= b;
				para_T0 += a;
				b = l >> 3;
				a = ~b;
				para_Q_H = l >> 6;
				para_Q_L = ~l;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = l >> 4;
				a = ~b;
				para_Q_L = ~para_Q_H;
				b = para_Q_L & l;
				a |= b;
				para_T0 += a;
				a = ~r;
				para_Q_H = r >> 6;
				para_Q_L = r >> 1;
				b = para_Q_H & para_Q_L;
				a |= b;
				para_T0 += a;
				b = r >> 4;
				a = ~b;
				c = ~para_Q_H;
				b = para_Q_L & c;
				a |= b;
				para_T0 += a;
				b = r >> 2;
				a = ~b;
				c = ~para_Q_L;
				b = para_Q_H & c;
				a |= b;
				para_T0 += a;
				para_Q_L = l >> 2;
				b = ~para_Q_L;
				a = b & c;
				a &= l;
				b = ~para_Q_H;
				para_Q_H = ~l;
				b &= para_Q_H;
				para_Q_H = m >> 5;
				b &= para_Q_H;
				a |= b;
				para_Q_H = r >> 3;
				para_Q_L &= para_Q_H;
				c = m >> 3;
				b = ~c;
				b &= para_Q_L;
				a |= b;
				para_Q_L = m >> 5;
				b = ~para_Q_L;
				c &= b;
				para_Q_L = r >> 1;
				b = ~para_Q_L;
				b &= para_Q_H;
				b |= c;
				para_Q_H = l >> 6;
				c = ~para_Q_H;
				b &= c;
				a |= b;
				para_T0 += a;
				b = para_T0 & 1;
			}
		}

		if (b == dev_aCT1[Tid][47])
		{
			dev_BiuKey[Tid][0] = 1;
			dev_BiuKey[Tid][1] = (Key7Byte_H >> 0x18) & 0xff;
			dev_BiuKey[Tid][2] = key & 0xff;
			dev_BiuKey[Tid][3] = (key >> 8) & 0xff;
			dev_BiuKey[Tid][4] = (key >> 0x10) & 0xff;
			dev_BiuKey[Tid][5] = (key >> 0x18) & 0xff;
			dev_BiuKey[Tid][6] = (Key7Byte_H >> 0x10) & 0xff;
			dev_BiuKey[Tid][7] = (Key7Byte_H >> 8) & 0xff;
			dev_BiuKey[Tid][8] = Key7Byte_H & 0xff;
			dev_BiuKey[Tid][9] = (Key7Byte_L >> 0x18) & 0xff;
			dev_BiuKey[Tid][10] = (Key7Byte_L >> 0x10) & 0xff;
			dev_BiuKey[Tid][11] = (Key7Byte_L >> 8) & 0xff;
			dev_BiuKey[Tid][12] = Key7Byte_L & 0xff;
		}
	}
	__syncthreads();
}


__device__ void SortCommonStateFirst(BiuState* __restrict__ Bs_Sp, BiuState* __restrict__ Bs_New, BiuState* __restrict__ Bs_Pre, 
				uint32_t* __restrict__ BiuCount, const uint8_t Tid)
{
	if (*BiuCount > BiuBufLen)
	{
		uint8_t fjal = 1;
	}
	
	RevSucFirst(Bs_Sp, Bs_Pre, BiuCount, Tid);	//0
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 1);	//1
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 2);	//2
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 3);	//3
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 4);	//4
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 5);	//5
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 6);	//6
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 7);	//7
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 8);	//8
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 9);	//9
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 10);	//10
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 11);	//11
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 12);	//12
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 13);	//13
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 14);	//14
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 15);	//15
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 16);	//16
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 17);	//17
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 18);	//18
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 19);	//19
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 20);	//20
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 21);	//21
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 22);	//22
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 23);	//23
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 24);	//24
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 25);	//25
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 26);	//26
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 27);	//27
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 28);	//28
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 29);	//29
	RevSucSecond(Bs_New, Bs_Pre, BiuCount, Tid, 30);	//30
	RevSucSecond(Bs_Pre, Bs_New, BiuCount, Tid, 31);	//31
	RevSucThird(Bs_New, Bs_Sp, BiuCount, Tid);	//32
}
__device__ void SortCommonStateMid(BiuState* __restrict__ Bs_Sp, BiuState* __restrict__ Bs_New, BiuState* __restrict__ Bs_Pre, BiuState* __restrict__ Bs_Mid,
				uint32_t* __restrict__ SpCount, uint32_t* __restrict__ BiuCount, uint32_t* __restrict__ MidCount, const uint8_t Tid)
{
	uint32_t idx, CalcCount, LastCount;
	LastCount = *SpCount % blockDim.x;
	CalcCount = *SpCount/ blockDim.x;
	if (*SpCount > BiuBufLen)
	{
		uint8_t fjal = 1;
	}
	

	//33-39
	for (idx = 0; idx < CalcCount; idx++)
	{
		*BiuCount = blockDim.x;
		RevSucSpFirst(Bs_Sp, Bs_New, BiuCount, idx*blockDim.x, Tid);	//33
		RevSucSpSecond(Bs_New, Bs_Pre, BiuCount, Tid);	//34
		RevSucSpSecond(Bs_Pre, Bs_New, BiuCount, Tid);	//35
		RevSucSpSecond(Bs_New, Bs_Pre, BiuCount, Tid);	//36
		RevSucSpSecond(Bs_Pre, Bs_New, BiuCount, Tid);	//37
		RevSucSpSecond(Bs_New, Bs_Pre, BiuCount, Tid);	//38
		RevSucSpSecond(Bs_Pre, Bs_New, BiuCount, Tid);	//39

		RevCheckInit(Bs_New, Bs_Pre, BiuCount, Tid);	//0-7
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 0, Tid);	//8
		RevCheckFirst(Bs_New, Bs_Pre, BiuCount, 1, Tid);	//9
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 2, Tid);	//10
		RevCheckFirst(Bs_New, Bs_Pre, BiuCount, 3, Tid);	//11
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 4, Tid);	//12
		RevCheckFirst(Bs_New, Bs_Pre, BiuCount, 5, Tid);	//13
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 6, Tid);	//14
		RevCheckFirst(Bs_New, Bs_Pre, BiuCount, 7, Tid);	//15
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 8, Tid);	//16
		RevCheckFirstToMid(Bs_New, Bs_Mid, BiuCount, MidCount, 9, Tid);	//17
	}

	//Last 33-39
	if (LastCount != 0)
	{
		*BiuCount = LastCount;
		RevSucSpFirst(Bs_Sp, Bs_New, BiuCount, idx*blockDim.x, Tid);	//33
		RevSucSpSecond(Bs_New, Bs_Pre, BiuCount, Tid);	//34
		RevSucSpSecond(Bs_Pre, Bs_New, BiuCount, Tid);	//35
		RevSucSpSecond(Bs_New, Bs_Pre, BiuCount, Tid);	//36
		RevSucSpSecond(Bs_Pre, Bs_New, BiuCount, Tid);	//37
		RevSucSpSecond(Bs_New, Bs_Pre, BiuCount, Tid);	//38
		RevSucSpSecond(Bs_Pre, Bs_New, BiuCount, Tid);	//39

		RevCheckInit(Bs_New, Bs_Pre, BiuCount, Tid);	//0-7
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 0, Tid);	//8
		RevCheckFirst(Bs_New, Bs_Pre, BiuCount, 1, Tid);	//9
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 2, Tid);	//10
		RevCheckFirst(Bs_New, Bs_Pre, BiuCount, 3, Tid);	//11
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 4, Tid);	//12
		RevCheckFirst(Bs_New, Bs_Pre, BiuCount, 5, Tid);	//13
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 6, Tid);	//14
		RevCheckFirst(Bs_New, Bs_Pre, BiuCount, 7, Tid);	//15
		RevCheckFirst(Bs_Pre, Bs_New, BiuCount, 8, Tid);	//16
		RevCheckFirstToMid(Bs_New, Bs_Mid, BiuCount, MidCount, 9, Tid);	//17
	}
}
__device__ void SortCommonStateEnd(BiuState* __restrict__ Bs_New, BiuState* __restrict__ Bs_Pre, BiuState* __restrict__ Bs_Mid,  
				uint32_t* __restrict__ MidCount, const uint8_t Tid)
{
	if (*MidCount > BiuBufLen)
	{
		uint8_t fja = 1;
	}
	
	//16-54
	RevCheckFirstFromMid(Bs_Mid, Bs_Pre, MidCount, 10, Tid);	//18
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 11, Tid);	//19
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 12, Tid);	//20
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 13, Tid);	//21
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 14, Tid);	//22
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 15, Tid);	//23
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 16, Tid);	//24
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 17, Tid);	//25
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 18, Tid);	//26
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 19, Tid);	//27
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 20, Tid);	//28
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 21, Tid);	//29
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 22, Tid);	//30
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 23, Tid);	//31
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 24, Tid);	//32
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 25, Tid);	//33
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 26, Tid);	//34
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 27, Tid);	//35
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 28, Tid);	//36
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 29, Tid);	//37
	RevCheckFirst(Bs_New, Bs_Pre, MidCount, 30, Tid);	//38
	RevCheckFirst(Bs_Pre, Bs_New, MidCount, 31, Tid);	//39
	RevCheckSecond(Bs_New, Bs_Pre, MidCount, 33, Tid);	//40
	RevCheckSecond(Bs_Pre, Bs_New, MidCount, 34, Tid);	//41
	RevCheckSecond(Bs_New, Bs_Pre, MidCount, 35, Tid);	//42
	RevCheckSecond(Bs_Pre, Bs_New, MidCount, 36, Tid);	//43
	RevCheckSecond(Bs_New, Bs_Pre, MidCount, 37, Tid);	//44
	RevCheckSecond(Bs_Pre, Bs_New, MidCount, 38, Tid);	//45
	RevCheckSecond(Bs_New, Bs_Pre, MidCount, 39, Tid);	//46
	RevCheckSecond(Bs_Pre, Bs_New, MidCount, 40, Tid);	//47
	RevCheckSecond(Bs_New, Bs_Pre, MidCount, 41, Tid);	//48
	RevCheckSecond(Bs_Pre, Bs_New, MidCount, 42, Tid);	//49
	RevCheckSecond(Bs_New, Bs_Pre, MidCount, 43, Tid);	//50
	RevCheckSecond(Bs_Pre, Bs_New, MidCount, 44, Tid);	//51
	RevCheckSecond(Bs_New, Bs_Pre, MidCount, 45, Tid);	//52
	RevCheckSecond(Bs_Pre, Bs_New, MidCount, 46, Tid);	//53
	RevCheckEnd(Bs_New, MidCount, Tid);	//54
}
__global__ void CudaCalcKey(BiuParaNode* Bpn, InitGH* Initgh, InitLMR* Initlmr, CommonHeadIndexStr* Chis, uint8_t Tid)
{
	uint32_t Bi = blockIdx.x;
	Bpn->MidCount[blockIdx.x] = 0;
	//Bpn->SpCount[blockIdx.x] = 0;
	for (Bi = blockIdx.x; Bi < 0x2000; Bi+=gridDim.x)
	{
		Bpn->BiuCount[blockIdx.x] = 0;
		Bpn->SpCount[blockIdx.x] = 0;
		PreSort(&Initgh[Chis[Bi*8].ThOffSetIndex], &Initlmr[Chis[Bi*8].TlmrOffSetIndex], &Chis[Bi*8], &Bpn->Bs_New[blockIdx.x], &Bpn->Bs_Pre[blockIdx.x], &Bpn->Bs_Sp[blockIdx.x], &Bpn->BiuCount[blockIdx.x], &Bpn->SpCount[blockIdx.x], Tid);
		SortCommonStateFirst(&Bpn->Bs_Sp[blockIdx.x], &Bpn->Bs_New[blockIdx.x], &Bpn->Bs_Pre[blockIdx.x], &Bpn->SpCount[blockIdx.x], Tid);
		SortCommonStateMid(&Bpn->Bs_Sp[blockIdx.x], &Bpn->Bs_New[blockIdx.x], &Bpn->Bs_Pre[blockIdx.x], &Bpn->Bs_Mid[blockIdx.x], &Bpn->SpCount[blockIdx.x], &Bpn->BiuCount[blockIdx.x], &Bpn->MidCount[blockIdx.x], Tid);
	}
	
	SortCommonStateEnd(&Bpn->Bs_New[blockIdx.x], &Bpn->Bs_Pre[blockIdx.x], &Bpn->Bs_Mid[blockIdx.x], &Bpn->MidCount[blockIdx.x], Tid);
}
__global__ void InitConstantPara(uint8_t* RndCipher, uint8_t Tid)
{
	uint64_t aCT = (((uint64_t)RndCipher[7] << 0x28) | ((uint64_t)RndCipher[8] << 0x20)
		| ((uint64_t)RndCipher[9] << 0x18) | ((uint64_t)RndCipher[0xA] << 0x10)
		| ((uint64_t)RndCipher[0xB] << 8) | (uint64_t)RndCipher[0xC]) >> 0xf;
	uint8_t i;
	//dev_Out7Bit[Tid] = RndCipher[0xc] & 0x7f;
	for (i = 0; i < 7; i++)
	{
		dev_Out7Bit[Tid][i] = ((RndCipher[0xc] & 0x7f) >> (6 - i)) & 1;
	}
	for (i = 0; i < 33; i++)
	{
		dev_aCT0[Tid][i] = (aCT >> i) & 1;
	}
	dev_nC0[Tid] = ((uint64_t)RndCipher[6] << 0x30) | ((uint64_t)RndCipher[5] << 0x28) | ((uint64_t)RndCipher[4] << 0x20)
				| ((uint64_t)RndCipher[3] << 0x18) | ((uint64_t)RndCipher[2] << 0x10) | ((uint64_t)RndCipher[1] << 8) 
				| (uint64_t)RndCipher[0];
	dev_nC1[Tid] = ((uint64_t)RndCipher[0x13] << 0x30) | ((uint64_t)RndCipher[0x12] << 0x28) | ((uint64_t)RndCipher[0x11] << 0x20)
				| ((uint64_t)RndCipher[0x10] << 0x18) | ((uint64_t)RndCipher[0xF] << 0x10) | ((uint64_t)RndCipher[0xE] << 8) 
				| (uint64_t)RndCipher[0xD];
	for (i = 0; i < 48; i++)
	{
		dev_aCT1[Tid][i] = (RndCipher[(i/8) + 0x14] >> (7-(i%8))) & 1;
	}
	for (i = 0; i < 13; i++)
	{
		dev_BiuKey[Tid][i] = 0;
	}
}

struct G_DataFileInFo{ uint16_t Index; uint32_t ThLen;uint32_t TlmrLen;};
struct G_DataFileInFoBlock{ G_DataFileInFo G_DFInFo[SubCpuThreadCount]; uint8_t OutByteIndex; };
struct G_DataFileInFoBlock* Local_G_DFInFoB = (struct G_DataFileInFoBlock*)calloc(1, sizeof(struct G_DataFileInFoBlock));
bool InitCalcPara(uint8_t* RndAndCipher, uint8_t Tid)
{
	cudaError_t ConstMemoryInitExit;
	uint8_t* devG1_RCTmp;
	ConstMemoryInitExit = cudaMalloc((uint8_t**)&devG1_RCTmp, sizeof(uint8_t)*26);
	if (ConstMemoryInitExit != cudaSuccess)
	{
		printf("Malloc devG1_RCTmp error!\n");
        return false;
	}
	ConstMemoryInitExit = cudaMemcpy(devG1_RCTmp, RndAndCipher, 26*sizeof(uint8_t), cudaMemcpyHostToDevice);
	if (ConstMemoryInitExit != cudaSuccess)
	{
		printf("Init devG1_RCTmp error!\n");
        return false;
	}
	InitConstantPara<<<1,1>>>(devG1_RCTmp, Tid);
	ConstMemoryInitExit = cudaDeviceSynchronize();
	if (ConstMemoryInitExit != cudaSuccess)
	{
		printf("InitConstantPara function error!\n");
        return false;
	}
	cudaFree(devG1_RCTmp);
	return true;
}

bool ReadFunc(uint8_t tId, uint16_t ID)
{
	string sTComHeadTmp = "/mnt/sd1/Tlmr/" + to_string(0xff) + "/CommonHead/";
	string sTlmrDataTmp = "/mnt/sd1/Tlmr/" + to_string(0xff) + "/Data/";
	string sThDataTmp = "/mnt/nv1/Th/Data/";

	{
		if (ReadTCBH_OP(Local_G_TCBS->G_TCB[tId].Tchis, ID, sTComHeadTmp) == false)
		{
			return false;
		}
		
		Local_G_DFInFoB->G_DFInFo[tId].TlmrLen = Local_G_TCBS->G_TCB[tId].Tchis[G_TCBHLen - 1].TlmrOffSetIndex + Local_G_TCBS->G_TCB[tId].Tchis[G_TCBHLen - 1].TlmrCount;
		Local_G_DFInFoB->G_DFInFo[tId].ThLen = Local_G_TCBS->G_TCB[tId].Tchis[G_TCBHLen - 1].ThOffSetIndex + Local_G_TCBS->G_TCB[tId].Tchis[G_TCBHLen - 1].ThCount;
		if ((Local_G_DFInFoB->G_DFInFo[tId].TlmrLen > G_TCBInitlmrLen) || (Local_G_DFInFoB->G_DFInFo[tId].ThLen > G_TCBInitghLen))
		{
			return false;
		}
		Local_G_DFInFoB->G_DFInFo[tId].TlmrLen *= sizeof(InitLMR);
		Local_G_DFInFoB->G_DFInFo[tId].ThLen *= sizeof(InitGH);

		if (ReadTlmr_OP(Local_G_TCBS->G_TCB[tId].TlmrInitlmr, Local_G_DFInFoB->G_DFInFo[tId].TlmrLen, ID, sTlmrDataTmp) == false)
		{
			return false;
		}

		if (ReadTh_OP(Local_G_TCBS->G_TCB[tId].ThInitgh, Local_G_DFInFoB->G_DFInFo[tId].ThLen, ID, sThDataTmp) == false)
		{
			return false;
		}
	}
	return true;
}


bool Decrypt(uint8_t* RndAndCipher) {
    cudaError_t cuResult;
    cudaStream_t streamTmp;
    if (cudaSetDevice(0) != cudaSuccess) {
        printf("cudaSetDevice error!\n");
        return false;
    }
    if (cudaStreamCreate(&streamTmp) != cudaSuccess) {
        return false;
    }
    uint8_t tId = 0;
    if (!InitCalcPara(RndAndCipher, tId)) {
        cudaStreamDestroy(streamTmp);
        return false;
    }
    BiuParaNode* dev_Bpn;
    G_TableCommonBlock* dev_GTCB;
    uint8_t* dev_Tid;
    if (cudaMalloc((void**)&dev_Bpn, sizeof(BiuParaNode)) != cudaSuccess ||
        cudaMalloc((void**)&dev_GTCB, sizeof(G_TableCommonBlock)) != cudaSuccess ||
        cudaMallocManaged((void**)&dev_Tid, sizeof(uint8_t)) != cudaSuccess) {
        cudaStreamDestroy(streamTmp);
        cudaFree(dev_Bpn);
        cudaFree(dev_GTCB);
        return false;
    }
    *dev_Tid = tId;

    uint8_t BiuKey[13] = {0};
    uint16_t ID = 0;
    if (!ReadFunc(tId, ID)) {
        cudaStreamDestroy(streamTmp);
        cudaFree(dev_Bpn);
        cudaFree(dev_GTCB);
        cudaFree(dev_Tid);
        free(Local_BPN);
        return false;
    }
    if (cudaMemcpyAsync(dev_GTCB, &Local_G_TCBS->G_TCB[0], sizeof(G_TableCommonBlock), cudaMemcpyHostToDevice, streamTmp) != cudaSuccess ||
        cudaStreamSynchronize(streamTmp) != cudaSuccess) {
        cudaStreamDestroy(streamTmp);
        cudaFree(dev_Bpn);
        cudaFree(dev_GTCB);
        cudaFree(dev_Tid);
        free(Local_BPN);
        return false;
    }

    const uint16_t maxID = 1000;
    while (ID < maxID) {
        cudaEvent_t e_start, e_end;
        cuResult = cudaEventCreate(&e_start);
        if (cuResult != cudaSuccess) {
            printf("host: cudaEventCreate e_start error %s\n", cudaGetErrorString(cuResult));
            cudaStreamDestroy(streamTmp);
            cudaFree(dev_Bpn);
            cudaFree(dev_GTCB);
            cudaFree(dev_Tid);
            free(Local_BPN);
            return false;
        }
        cuResult = cudaEventCreate(&e_end);
        if (cuResult != cudaSuccess) {
            printf("host: cudaEventCreate e_end error %s\n", cudaGetErrorString(cuResult));
            cudaEventDestroy(e_start);
            cudaStreamDestroy(streamTmp);
            cudaFree(dev_Bpn);
            cudaFree(dev_GTCB);
            cudaFree(dev_Tid);
            free(Local_BPN);
            return false;
        }
        cuResult = cudaEventRecord(e_start, streamTmp);
        if (cuResult != cudaSuccess) {
            printf("host: cudaEventRecord e_start error %s\n", cudaGetErrorString(cuResult));
            cudaEventDestroy(e_start);
            cudaEventDestroy(e_end);
            cudaStreamDestroy(streamTmp);
            cudaFree(dev_Bpn);
            cudaFree(dev_GTCB);
            cudaFree(dev_Tid);
            free(Local_BPN);
            return false;
        }

        CudaCalcKey<<<kernelblock, kernelthread, 0, streamTmp>>>(dev_Bpn, dev_GTCB->ThInitgh, dev_GTCB->TlmrInitlmr, dev_GTCB->Tchis, *dev_Tid);
        cuResult = cudaGetLastError();
        if (cuResult != cudaSuccess) {
            printf("host: SubCalcState_v2 error %s\n", cudaGetErrorString(cuResult));
            cudaEventDestroy(e_start);
            cudaEventDestroy(e_end);
            cudaStreamDestroy(streamTmp);
            cudaFree(dev_Bpn);
            cudaFree(dev_GTCB);
            cudaFree(dev_Tid);
            free(Local_BPN);
            return false;
        }
        cuResult = cudaEventRecord(e_end, streamTmp);
        if (cuResult != cudaSuccess) {
            printf("host: cudaEventRecord e_end error %s\n", cudaGetErrorString(cuResult));
            cudaEventDestroy(e_start);
            cudaEventDestroy(e_end);
            cudaStreamDestroy(streamTmp);
            cudaFree(dev_Bpn);
            cudaFree(dev_GTCB);
            cudaFree(dev_Tid);
            free(Local_BPN);
            return false;
        }
        cuResult = cudaEventSynchronize(e_end);
        if (cuResult != cudaSuccess) {
            printf("host: cudaEventSynchronize error %s\n", cudaGetErrorString(cuResult));
            cudaEventDestroy(e_start);
            cudaEventDestroy(e_end);
            cudaStreamDestroy(streamTmp);
            cudaFree(dev_Bpn);
            cudaFree(dev_GTCB);
            cudaFree(dev_Tid);
            free(Local_BPN);
            return false;
        }
        cudaEventDestroy(e_start);
        cudaEventDestroy(e_end);

        cudaMemcpyAsync(Local_BPN->SpCount, dev_Bpn->SpCount, sizeof(uint32_t) * kernelblock, cudaMemcpyDeviceToHost, streamTmp);
        cudaStreamSynchronize(streamTmp);

        cudaError_t mR = cudaMemcpyFromSymbol(BiuKey, dev_BiuKey, 13 * sizeof(uint8_t), 0, cudaMemcpyDeviceToHost);
        if (mR != cudaSuccess) {
            printf("cudaMemcpyFromSymbol error: %s\n", cudaGetErrorString(mR));
            cudaStreamDestroy(streamTmp);
            cudaFree(dev_Bpn);
            cudaFree(dev_GTCB);
            cudaFree(dev_Tid);
            free(Local_BPN);
            return false;
        }
        if (BiuKey[0] == 1) {
            gettimeofday(&end_time, NULL);
            cudaStreamDestroy(streamTmp);
            cudaFree(dev_Bpn);
            cudaFree(dev_GTCB);
            cudaFree(dev_Tid);
            free(Local_BPN);
            return true;
        }
        memset(Local_BPN, 0, sizeof(BiuParaNode));
        ID++;
    }

    gettimeofday(&end_time, NULL);
    cudaStreamDestroy(streamTmp);
    cudaFree(dev_Bpn);
    cudaFree(dev_GTCB);
    cudaFree(dev_Tid);
    free(Local_BPN);
    return false;
}

int main() {
    uint8_t RndCipher[0x1a] = {
        0x19, 0x88, 0x53, 0x40, 0x78, 0xFD, 0x4A, 0x73, 0x0a, 0x61, 0x36, 0x7f, 0xe5,
        0x2d, 0x49, 0xc3, 0x8c, 0xe2, 0xd7, 0xe2, 0x7f, 0xf7, 0x3e, 0x8d, 0x05, 0x5a
    };

    cudaEvent_t start_event, end_event;
    float cuda_time_ms;
    cudaEventCreate(&start_event);
    cudaEventCreate(&end_event);
    cudaEventRecord(start_event, 0);

    gettimeofday(&start, NULL);
    if (Decrypt(RndCipher)) {
        long time_usec = 1000000 * (end_time.tv_sec - start.tv_sec) + (end_time.tv_usec - start.tv_usec);
        uint8_t BiuKey[13];
        cudaError_t mR = cudaMemcpyFromSymbol(BiuKey, dev_BiuKey, 13 * sizeof(uint8_t), 0, cudaMemcpyDeviceToHost);
        if (mR != cudaSuccess) {
            printf("cudaMemcpyFromSymbol error: %s\n", cudaGetErrorString(mR));
            cudaEventDestroy(start_event);
            cudaEventDestroy(end_event);
            return 1;
        }
        cudaEventRecord(end_event, 0);
        cudaEventSynchronize(end_event);
        cudaEventElapsedTime(&cuda_time_ms, start_event, end_event);
        printf("Success! Time: %ld us (CUDA: %.2f ms)\nKey: ", time_usec, cuda_time_ms);
        for (int i = 1; i < 13; i++) printf("%02x ", BiuKey[i]);
        printf("\n");
    } else {
        printf("Decrypt failed\n");
    }

    cudaEventDestroy(start_event);
    cudaEventDestroy(end_event);
    return 0;
}
//////////////////////一个内核函数，筛选8行表