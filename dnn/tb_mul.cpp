#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vmul.h"
#include <iostream>
#include <cstdlib>
#include <limits>

class MulTester {
    Vmul* dut;
    VerilatedVcdC* tfp;
    vluint64_t sim_time;
    bool trace_en;
    
public:
    MulTester(bool trace = false) : trace_en(trace), sim_time(0) {
        dut = new Vmul;
        Verilated::traceEverOn(trace);
        if (trace) {
            tfp = new VerilatedVcdC;
            dut->trace(tfp, 99);
            tfp->open("mul_waves.vcd");
        }
        reset();
    }

    ~MulTester() {
        if (trace_en) tfp->close();
        delete dut;
    }

    void reset() {
        dut->rst = 1;
        tick();
        dut->rst = 0;
        tick();
    }

    void tick() {
        dut->clk = 0;
        dut->eval();
        if (trace_en) tfp->dump(sim_time++);
        
        dut->clk = 1;
        dut->eval();
        if (trace_en) tfp->dump(sim_time++);
    }

    uint64_t multiply(uint32_t a, uint32_t b) {
        dut->a = a;
        dut->b = b;
        dut->valid = 1;
        
        while (!dut->ready) {
            tick();
        }
        uint64_t res = dut->result;
        
        dut->valid = 0;
        tick(); // Return to WAIT state
        
        return res;
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    MulTester tb(true); // Enable waveform tracing
    
    // Test vectors: {a, b}
    std::vector<std::pair<int32_t, int32_t>> tests = {
        {0, 0},
        {1, 1},
        {5, 7},
        {-2, 4},
        {3, -5},
        {-4, -6},
        {0x7FFFFFFF, 1},   // MAX_INT32
        {0x80000000, 1},   // MIN_INT32
        {0x12345678, 0x9ABCDEF0}
    };
    
    for (auto& test : tests) {
        int32_t a = test.first;
        int32_t b = test.second;
        int64_t expected = static_cast<int64_t>(a) * static_cast<int64_t>(b);
        uint64_t actual = tb.multiply(static_cast<uint32_t>(a), 
                                     static_cast<uint32_t>(b));
        
        std::cout << "Test: " << a << " * " << b << " = " 
                  << "Expected: " << expected << " (" << std::hex << expected
                  << "), Got: " << actual << " (" << std::hex << actual << ")\n";
                  
        if (static_cast<int64_t>(actual) != expected) {
            std::cerr << "MISMATCH!\n";
            return 1;
        }
    }
    
    std::cout << "All tests passed!\n";
    return 0;
}

