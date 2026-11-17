#include "coremark.h"
#ifndef ITERATIONS
#define ITERATIONS 10
#endif
#ifndef CPU_HZ
#define CPU_HZ 50000000
#endif
#if VALIDATION_RUN
volatile ee_s32 seed1_volatile=0x3415, seed2_volatile=0x3415;
#else
volatile ee_s32 seed1_volatile=0, seed2_volatile=0;
#endif
volatile ee_s32 seed3_volatile=0x66;
volatile ee_s32 seed4_volatile=ITERATIONS, seed5_volatile=7;
ee_u32 default_num_contexts=1;
static ee_u32 begin_cycle,end_cycle,begin_inst,end_inst;
static ee_u32 cycle(void) { ee_u32 x; __asm__ volatile("csrr %0, mcycle":"=r"(x)::"memory"); return x; }
static ee_u32 instret(void) { ee_u32 x; __asm__ volatile("csrr %0, minstret":"=r"(x)::"memory"); return x; }
void start_time(void) { begin_inst=instret();begin_cycle=cycle(); }
void stop_time(void) { end_cycle=cycle();end_inst=instret(); }
CORE_TICKS get_time(void) { return end_cycle-begin_cycle; }
secs_ret time_in_secs(CORE_TICKS ticks) { return ticks/CPU_HZ; }
void portable_init(core_portable *p,int *argc,char *argv[]) { (void)argc;(void)argv;p->portable_id=1; }
void portable_fini(core_portable *p) {
    p->portable_id=0;
    ee_printf("RTL retired      : %lu\n",(unsigned long)(end_inst-begin_inst));
}
void *memcpy(void *d,const void *s,size_t n) {
    unsigned char *a=d;const unsigned char *b=s;while(n--)*a++=*b++;return d;
}
void *memset(void *d,int v,size_t n) {
    unsigned char *a=d;while(n--)*a++=(unsigned char)v;return d;
}
