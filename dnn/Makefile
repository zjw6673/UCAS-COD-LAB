MODULE ?= mul

default: test

test: $(MODULE).v tb_$(MODULE).cpp
	verilator -Wall -cc --exe --trace $(MODULE).v tb_$(MODULE).cpp
	$(MAKE) -C obj_dir -f V$(MODULE).mk V$(MODULE)
	./obj_dir/V$(MODULE)

.PHONY: clean
clean:
	-rm -rf ./obj_dir
	-rm -rf *.vcd
