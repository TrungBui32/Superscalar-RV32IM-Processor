#include "Vcoremark_sim.h"
#include "verilated.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
static double sim_time=0;
double sc_time_stamp(){return sim_time;}
int main(int argc,char **argv){
    Verilated::commandArgs(argc,argv);
    uint64_t limit=100000000,hz=50000000;
    for(int i=1;i<argc;i++)if(!strncmp(argv[i],"+limit=",7))limit=strtoull(argv[i]+7,nullptr,10);
    for(int i=1;i<argc;i++)if(!strncmp(argv[i],"+hz=",4))hz=strtoull(argv[i]+4,nullptr,10);
    Vcoremark_sim dut;
    // sc_time_stamp uses the model's global precision (1 ps here), not ns.
    const double ticks_per_second=std::pow(10.0,-Verilated::timeprecision());
    const double half_period=ticks_per_second/(2.0*double(hz));
    dut.rst=1;
    for(int i=0;i<4;i++){dut.clk=0;dut.eval();sim_time+=half_period;dut.clk=1;dut.eval();sim_time+=half_period;}
    dut.rst=0;
    const auto start=std::chrono::steady_clock::now();
    while(!dut.done && !Verilated::gotFinish() && dut.cycles<limit){
        dut.clk=0;dut.eval();sim_time+=half_period;
        dut.clk=1;dut.eval();sim_time+=half_period;
        if(dut.cycles && dut.cycles%1000000==0){
            double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
            fprintf(stderr,"PROGRESS cycles=%llu pc=%08x host_seconds=%.3f\n",(unsigned long long)dut.cycles,dut.pc,elapsed);
        }
    }
    const bool pass=dut.done && !dut.failed;
    double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
    printf("RTL_FINISH status=%s cycles=%llu pc=%08x hz=%llu host_seconds=%.6f simulated_seconds=%.9f\n",pass?"PASS":"FAIL",(unsigned long long)dut.cycles,dut.pc,(unsigned long long)hz,elapsed,sim_time/ticks_per_second);
    dut.final();return pass?0:1;
}
