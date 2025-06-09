#include "printf.h"
#include "trap.h"
#include "mul.h"
#include "div.h"
#include "perf_cnt.h"

#define FRAC_BIT 10

#define RD_ADDR 135106448
#define RD_SIZE_D0 1
#define RD_SIZE_D1 1 // one channel
#define RD_SIZE_D2 28
#define RD_SIZE_D3 28 // 28 shorts, namely 56 bytes

#define WEIGHT_ADDR 134217728
#define WEIGHT_SIZE_D0 20 // output 20 channel, namely 20 different kernels
#define WEIGHT_SIZE_D1 1 // input 1 channel, so each kernel has only one layer
#define WEIGHT_SIZE_D2 5
#define WEIGHT_SIZE_D3 5 // 5 * 5 = 25 shorts, namely 50 bytes, plus 2-byte bias in the begining

#define WR_ADDR 135108240
#define WR_SIZE_D0 1
#define WR_SIZE_D1 20 // 20 channel
#define WR_SIZE_D2 12
#define WR_SIZE_D3 12 // 12 shorts, namely 24 bytes, no blank for alignment

#define KERN_ATTR_CONV_PAD 0
#define KERN_ATTR_CONV_STRIDE 1
#define KERN_ATTR_POOL_PAD 0
#define KERN_ATTR_POOL_KERN_SIZE 2
#define KERN_ATTR_POOL_STRIDE 2

//MMIO register address of DNN accelerator
#define GPIO_START_ADDR    0x60030000
#define GPIO_DONE_ADDR     0x60030008

struct size_vec4
{
	unsigned d0;
	unsigned d1;
	unsigned d2;
	unsigned d3;
};

struct mem_addr
{
	unsigned rd_addr;
	unsigned weight_addr;
	unsigned wr_addr;
};

int mul(short a, short b)
{
#ifndef USE_MUL
	int ans = mul_ll(a, b);
#else
	int ans = a * b;
#endif
	return ans;
}

struct mem_addr addr = {RD_ADDR, WEIGHT_ADDR, WR_ADDR};
struct size_vec4 rd_size = {RD_SIZE_D0, RD_SIZE_D1, RD_SIZE_D2, RD_SIZE_D3};
struct size_vec4 wr_size = {WR_SIZE_D0, WR_SIZE_D1, WR_SIZE_D2, WR_SIZE_D3};
struct size_vec4 weight_size = {WEIGHT_SIZE_D0, WEIGHT_SIZE_D1, WEIGHT_SIZE_D2, WEIGHT_SIZE_D3};

struct size_vec4 conv_size;

extern char _binary_data_result_bin_start[];
extern char _binary_data_result_bin_size[];

void convolution()
{
	short *in = (short *)addr.rd_addr;
	short *weight = (short *)addr.weight_addr;
	short *out = (short *)addr.wr_addr;

	// unsigned output_offset = 0;
	// unsigned input_offset = 0;

	unsigned input_fm_w = rd_size.d3; // 28 shorts
	unsigned input_fm_h = rd_size.d2; // 28 shorts

	/* calculate conv_out_w and conv_out_h */
	unsigned pad = KERN_ATTR_CONV_PAD;
	unsigned pad_len = pad << 1;

	unsigned conv_out_w = rd_size.d3 - weight_size.d3 + pad_len;
	unsigned conv_out_h = rd_size.d2 - weight_size.d2 + pad_len;

	unsigned stride = KERN_ATTR_CONV_STRIDE;

	conv_out_w = div(conv_out_w, stride);
	conv_out_h = div(conv_out_h, stride);

	conv_out_w++;
	conv_out_h++;

	conv_size.d0 = wr_size.d0;
	conv_size.d1 = wr_size.d1;
	conv_size.d2 = conv_out_h;
	conv_size.d3 = conv_out_w;

	//TODO: Please add your implementation here
	
	/* calculate sizes */
	short FilterSize = 1 + mul(weight_size.d2, weight_size.d3); // bias + 5 * 5 weights
	short InputSize = mul(input_fm_w, input_fm_h);
	short OutputSize = mul(conv_size.d2, conv_size.d3);

	for (short ch = 0; ch < conv_size.d1; ch++) { // for each output channel
		short bias = *weight;
		short *filter = weight + 1;

		short *channel_out = out; // output to this channel

		for (short r = 0; r < conv_out_h; r++) { // for each output row
			short r_base = mul(r, (short)stride) - pad; // base row in input
			
			for (short c = 0; c < conv_out_w; c++) { // for each output col
				short c_base = mul(c, (short)stride) - pad; // base col in input
				
				int result = 0; // store in in to avoid overflow

				short *filter_ptr = filter;
				short *input_ch = in;
				for (short n = 0; n < rd_size.d1; n++) { // for each input channel
					for (short i = 0; i < weight_size.d2; i++) { // filter rows
						short h_pos = r_base + i;

						for (short j = 0; j < weight_size.d3; j++) { // filter cols
							short w_pos = c_base + j;
							
							if (h_pos >= 0 && h_pos < input_fm_h && w_pos >= 0 && w_pos < input_fm_w) { // not in padding
								short input_val = input_ch[mul(h_pos, (short)input_fm_w) + w_pos];
								result += mul(input_val, *filter_ptr);
							}
							filter_ptr++; // since weight array is consecutive, inc directly
						}
					}
					input_ch += InputSize; // next input channel
				}

				// store result
				channel_out[mul(r, (short)conv_size.d3) + c] = (short)(result >> FRAC_BIT) + bias;
			}
		}

		weight += FilterSize; // next filter
		out += OutputSize; // next output channel
	}

}

void pooling()
{
	short *out = (short *)addr.wr_addr;

	// unsigned output_offset = 0;
	// unsigned input_offset = 0;

	unsigned input_fm_w = conv_size.d3;
	unsigned input_fm_h = conv_size.d2;

	unsigned pad = KERN_ATTR_POOL_PAD;
	unsigned pad_len = pad << 1;

	unsigned pad_w_test = conv_size.d3 - KERN_ATTR_POOL_KERN_SIZE;
	unsigned pad_h_test = conv_size.d2 - KERN_ATTR_POOL_KERN_SIZE;

	unsigned pool_out_w = pad_w_test + pad_len;
	unsigned pool_out_h = pad_h_test + pad_len;

	unsigned stride = KERN_ATTR_POOL_STRIDE;

	unsigned pad_w_test_remain = pad_w_test - mul(div(pad_w_test, stride), stride);
	unsigned pad_h_test_remain = pad_h_test - mul(div(pad_h_test, stride), stride);

	pool_out_w = div(pool_out_w, stride);
	pool_out_h = div(pool_out_h, stride);
	pool_out_w++;
	pool_out_h++;

	if ((!pad) && (pad_w_test_remain || pad_h_test_remain))
	{
		pool_out_w++;
		pool_out_h++;
	}

	//TODO: Please add your implementation here
	
	// calculate size
	short InputSize = mul(input_fm_h, input_fm_w);
	short OutputSize = mul(pool_out_h, pool_out_w);

	short *ch_input = out;
	short *ch_output = out;

	for (short ch = 0; ch < conv_size.d1; ch++) { // for each channel
		for (short r = 0; r < pool_out_h; r++) { // for each output row
			short r_base = mul(r, (short)stride) - pad;

			for (short c = 0; c < pool_out_w; c++) { // for each output col
				short c_base = mul(c, (short)stride) - pad;

				short max_val = 0x8000; // min short value

				for (short i = 0; i < KERN_ATTR_POOL_KERN_SIZE; i++) { // pool rows
					short h_pos = r_base + i;

					for (short j = 0; j < KERN_ATTR_POOL_KERN_SIZE; j++) { // pool cols
						short w_pos = c_base + j;

						if (h_pos >= 0 && h_pos < input_fm_h && w_pos >= 0 && w_pos < input_fm_w) { // not in padding
							short val = ch_input[mul(h_pos, (short)input_fm_w) + w_pos];
							if (val > max_val) max_val = val;
						}
					}
				}
				// write output
				ch_output[mul(r, (short)pool_out_w) + c] = max_val;
			}
		}
		// next channel
		ch_input += InputSize;
		ch_output += OutputSize;
	}
}

#ifdef USE_HW_ACCEL
void launch_hw_accel()
{
	volatile int* gpio_start = (void*)(GPIO_START_ADDR);
	volatile int* gpio_done = (void*)(GPIO_DONE_ADDR);

	//TODO: Please add your implementation here

	*gpio_start = 1;
	while (*(gpio_done) != 1);
	*gpio_start = 0;
}
#endif

int comparing()
{
	char *out = (char *)addr.wr_addr;
	char *result = (char *)_binary_data_result_bin_start;

#ifdef USE_HW_ACCEL
	int count = (int)_binary_data_result_bin_size + 
		    (16 - WR_SIZE_D3) * 2 * WR_SIZE_D2 * WR_SIZE_D1;
#else
	int count = (int)_binary_data_result_bin_size;
#endif

	for (int i = 0, j = 0; i < count; i++)
	{
#ifdef USE_HW_ACCEL
		int alignment = i & 0x0000001f;
		if (alignment >= (WR_SIZE_D3 << 1))
			continue;
#endif
		if (*(out + i) != *(result + j))
		{
			printf("Failed! at address %x and %x with data %x and %x\n", out + i, result + j, *(out + i), *(result + j));
			return 1;
		}
		j++;
	}

	printf("Passed!\n");
	return 0;
}

int main()
{
	Result res;
	res.msec = 0;

	bench_prepare(&res);

#ifdef USE_HW_ACCEL
	printf("Launching task...\n");
	launch_hw_accel();
#else
	printf("starting convolution\n");
	convolution();
	printf("starting pooling\n");
	pooling();
#endif

	int result = comparing();

	bench_done(&res);
      	printf("========== Performance Counter ==========\n");
      	printf("Clock cycle count: %d\n", res.msec);
      	printf("=========================================\n");

	printf("benchmark finished\n");


	if (result == 0) {
		hit_good_trap();
	} else {
		nemu_assert(0);
	}

	return 0;
}
