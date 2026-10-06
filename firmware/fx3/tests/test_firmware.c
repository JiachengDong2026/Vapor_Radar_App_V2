#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
static uint32_t mock_bus = 0x10ac, mock_wave = 0x010c0301, mock_status = 0x000f0000;
#define VAPOR_GPIF_BUS_CONFIG mock_bus
#define VAPOR_GPIF_WAVE_STATUS mock_wave
#define VAPOR_GPIF_STATUS mock_status
#define main firmware_main
#include "../src/cyfxslfifosync.c"
#undef main
#include "../src/cyfxslfifousbdscr.c"

static int created, armed, destroyed, disabled, reset_count, ack_count, active_ep;
static CyU3PUSBSpeed_t speed=CY_U3P_SUPER_SPEED;
static uint8_t status_reply[32];
static uint16_t reply_length;
void CyU3PMemSet(uint8_t *p,uint8_t d,uint32_t n) {memset(p,d,n);}
UINT _tx_thread_sleep(ULONG ticks) {fprintf(stderr,"Unexpected firmware fatal %lu\n",(unsigned long)glLastError);abort();}
CyU3PUSBSpeed_t CyU3PUsbGetSpeed(void) {return speed;}
CyU3PReturnStatus_t CyU3PSetEpConfig(uint8_t ep,CyU3PEpConfig_t *c) {
    assert(ep==0x02||ep==0x86);
    if(c->enable){assert(c->epType==CY_U3P_USB_EP_BULK);assert(c->pcktSize==(speed==CY_U3P_SUPER_SPEED?1024:speed==CY_U3P_HIGH_SPEED?512:64));assert(c->burstLen==(speed==CY_U3P_SUPER_SPEED?16:1));++active_ep;}
    else --active_ep;
    return CY_U3P_SUCCESS;
}
CyU3PReturnStatus_t CyU3PDmaChannelCreate(CyU3PDmaChannel *h,CyU3PDmaType_t t,CyU3PDmaChannelConfig_t *c) {
    assert(t==CY_U3P_DMA_TYPE_AUTO_SIGNAL);assert(c->size==16384&&c->count==4);
    assert(c->prodHeader==0&&c->prodFooter==0&&c->consHeader==0&&c->prodAvailCount==0);
    assert(c->dmaMode==CY_U3P_DMA_MODE_BYTE);
    if(h==&glChHandleSlFifoUtoP){assert(c->prodSckId==CY_U3P_UIB_SOCKET_PROD_2&&c->consSckId==CY_U3P_PIB_SOCKET_3);}
    else {assert(h==&glChHandleSlFifoPtoU);assert(c->prodSckId==CY_U3P_PIB_SOCKET_0&&c->consSckId==CY_U3P_UIB_SOCKET_CONS_6);}
    ++created;return CY_U3P_SUCCESS;
}
CyU3PReturnStatus_t CyU3PDmaChannelSetXfer(CyU3PDmaChannel *h,uint32_t count){assert(count==0);++armed;return CY_U3P_SUCCESS;}
CyU3PReturnStatus_t CyU3PDmaChannelDestroy(CyU3PDmaChannel *h){assert(disabled);++destroyed;return CY_U3P_SUCCESS;}
CyU3PReturnStatus_t CyU3PDmaChannelReset(CyU3PDmaChannel *h){++reset_count;return CY_U3P_SUCCESS;}
CyU3PReturnStatus_t CyU3PUsbFlushEp(uint8_t ep){assert(ep==2||ep==0x86);return CY_U3P_SUCCESS;}
CyU3PReturnStatus_t CyU3PUsbResetEp(uint8_t ep){assert(ep==2||ep==0x86);return CY_U3P_SUCCESS;}
CyU3PReturnStatus_t CyU3PGpifLoad(const CyU3PGpifConfig_t *c){assert(c==&Sync_Slave_Fifo_2Bit_CyFxGpifConfig);return CY_U3P_SUCCESS;}
CyU3PReturnStatus_t CyU3PGpifSocketConfigure(uint8_t thread,CyU3PDmaSocketId_t socket,uint16_t watermark,CyBool_t flag,uint8_t burst){assert((thread==0&&socket==CY_U3P_PIB_SOCKET_0)||(thread==3&&socket==CY_U3P_PIB_SOCKET_3));assert(watermark==12&&flag==CyFalse&&burst==1);return CY_U3P_SUCCESS;}
CyU3PReturnStatus_t CyU3PGpifSMStart(uint8_t state,uint8_t alpha){assert(armed>=2&&active_ep==2);assert(state==0&&alpha==12);disabled=0;return CY_U3P_SUCCESS;}
void CyU3PGpifDisable(CyBool_t force){assert(force==CyFalse);disabled=1;}
CyU3PReturnStatus_t CyU3PUsbStall(uint8_t ep,CyBool_t stall,CyBool_t toggle){assert(ep==0||ep==2||ep==0x86);return CY_U3P_SUCCESS;}
void CyU3PUsbAckSetup(void){++ack_count;}
CyU3PReturnStatus_t CyU3PUsbSendEP0Data(uint16_t n,uint8_t *p){assert(n<=32);memcpy(status_reply,p,n);reply_length=n;return CY_U3P_SUCCESS;}

static void descriptors(const uint8_t *d,size_t n,int superspeed) {
    size_t i=0;int endpoints=0,companions=0;
    assert(d[2]+256*d[3]==n);
    while(i<n){assert(d[i]>=2&&i+d[i]<=n);if(d[i+1]==5){assert(d[i+2]==(endpoints?0x86:2));++endpoints;}if(d[i+1]==48){assert(d[i+2]==15);++companions;}i+=d[i];}
    assert(endpoints==2&&companions==(superspeed?2:0));
}
int main(void) {
    uint32_t *r=Sync_Slave_Fifo_2Bit_CyFxGpifRegValue;
    int i;
    assert((r[0]&(1u<<4))==0&&(r[0]&(1u<<9))!=0); /* External PCLK, 50–100 MHz. */
    assert((r[1]&12)==12); /* DQ32. */
    assert((r[1]&CY_U3P_GPIF_PIN_COUNT_MASK)==0); /* DQ32 + 13 CTL + PCLK: 47-pin mode. */
    assert(Sync_Slave_Fifo_2Bit_CyFxGpifConfig.stateCount==199);
    for(i=0;i<13;++i)assert(((r[9]>>(2*i))&3)==((i==4||i==5||i==6||i==8)?1:0));
    assert(r[13+4]==16&&r[13+5]==19&&r[13+6]==20&&r[13+8]==23);
    assert((r[10]&0x170)==0&&(r[11]&0x1ff)==0x1ff);
    descriptors(CyFxUSBSSConfigDscr,sizeof(CyFxUSBSSConfigDscr),1);
    descriptors(CyFxUSBHSConfigDscr,sizeof(CyFxUSBHSConfigDscr),0);
    descriptors(CyFxUSBFSConfigDscr,sizeof(CyFxUSBFSConfigDscr),0);
    CyFxSlFifoApplnUSBEventCB(CY_U3P_USB_EVENT_SETCONF,1);
    assert(glIsApplnActive&&created==2&&armed==2);
    assert(glGpifPhase==4&&glErrorsBeforeStart==0&&glErrorsAfterStart==0);
    CyFxSlFifoUtoPDmaCallback(0,CY_U3P_DMA_CB_PROD_EVENT,0);
    CyFxSlFifoPtoUDmaCallback(0,CY_U3P_DMA_CB_ERROR,0);
    CyFxPibCallback(CYU3P_PIB_INTR_ERROR,7);
    assert(CyFxSlFifoApplnUSBSetupCB(0xB0C0,32u<<16));
    assert(reply_length==32&&((uint32_t*)status_reply)[0]==VAPOR_MAPPING_VERSION&&((uint32_t*)status_reply)[2]==1&&((uint32_t*)status_reply)[3]==1);
    assert(CyFxSlFifoApplnUSBSetupCB(0xB0C0,4u<<16)&&reply_length==4);
    assert(!CyFxSlFifoApplnUSBSetupCB(0xB040,0)); /* No write vendor command. */
    assert(CyFxSlFifoApplnUSBSetupCB(0xB1C0,64u<<16));
    assert(reply_length==32);
    assert(((uint32_t*)status_reply)[0]==0x31305047u);
    assert(((uint32_t*)status_reply)[1]==mock_bus&&((uint32_t*)status_reply)[2]==mock_wave);
    assert(((uint32_t*)status_reply)[3]==mock_status);
    assert(((uint32_t*)status_reply)[4]==4&&((uint32_t*)status_reply)[5]==4);
    assert(glPibErrors==1&&glLastError==0x80000007u); /* Reading keeps errors. */
    assert(CyFxSlFifoApplnUSBSetupCB(0xB1C0,4u<<16)&&reply_length==4);
    assert(!CyFxSlFifoApplnUSBSetupCB(0xB140,0));
    assert(!CyFxSlFifoApplnUSBSetupCB(0x1B1C0,32u<<16));
    assert(!CyFxSlFifoApplnUSBSetupCB(0xB1C0,(32u<<16)|1));
    assert(CyFxSlFifoApplnUSBSetupCB(0x00000102,0x86)); /* CLEAR_FEATURE endpoint halt. */
    assert(reset_count==1&&ack_count==1);
    assert(!CyFxSlFifoApplnUSBSetupCB(0x00000102,0x87));
    CyFxSlFifoApplnUSBEventCB(CY_U3P_USB_EVENT_RESET,0);
    assert(!glIsApplnActive&&active_ep==0&&destroyed==2&&disabled);
    CyFxSlFifoApplnUSBEventCB(CY_U3P_USB_EVENT_SETCONF,0);
    assert(!glIsApplnActive&&created==2);
    speed=CY_U3P_HIGH_SPEED;CyFxSlFifoApplnUSBEventCB(CY_U3P_USB_EVENT_SETCONF,1);
    CyFxSlFifoApplnUSBEventCB(CY_U3P_USB_EVENT_DISCONNECT,0);
    speed=CY_U3P_FULL_SPEED;CyFxSlFifoApplnUSBEventCB(CY_U3P_USB_EVENT_SETCONF,1);
    CyFxSlFifoApplnUSBEventCB(CY_U3P_USB_EVENT_SETCONF,0);
    assert(active_ep==0&&destroyed==6);
    puts("FX3_FIRMWARE_API_REGRESSION_PASS SS_HS_FS reset disconnect clear_halt diagnostics flags DMA");
    return 0;
}
