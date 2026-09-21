.PHONY: check board-project xv6
check:
	python3 tools/check.py
board-project:
	python3 tools/prepare-board.py
xv6:
	$(MAKE) -B -C software/xv6 kernel/kernel fs.img CPPFLAGS=-DTEACHING_SIM_MEM_MIB=128 $(if $(TOOLPREFIX),TOOLPREFIX=$(TOOLPREFIX),)
