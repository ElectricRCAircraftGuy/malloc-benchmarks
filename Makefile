#
# This makefile will build a small benchmarking utility for 'malloc' implementations and will
# run it with different implementations, first saving results into JSON files, and then plotting
# them graphically.
#
# Specifically, this makefile downloads, configures and compiles these different software packages:
# 1. GNU libc
# 2. Google perftools (tcmalloc)
# 3. jemalloc
# 4. fast_malloc
#   1. fast_malloc_1MiB = with a 1 MiB static heap
#   2. fast_malloc_1GiB = with a 1 GiB static heap
#
# First tested with these versions:
# 1. GNU libc 2.26
# 2. Google perftools (tcmalloc) 2.6.3
# 3. jemalloc 5.0.1
#
# Most-recently tested on Ubuntu 20.04 with these versions:
# 1. GNU libc 2.31
# 2. Google perftools (tcmalloc) 2.9.1
# 3. jemalloc 5.2.1-742
# 4. fast_malloc 0.1.0
#
#
# References:
# 1. How to use bash if/else statements inside makefiles:
#    https://stackoverflow.com/a/58602879/4561887
# 1. Meaning of the variable `MAKE` in a Makefile: https://stackoverflow.com/a/68240460/4561887
# 1. Phony targets: https://www.gnu.org/software/make/manual/html_node/Phony-Targets.html
#

#
# Parameters from command line
#

ifdef NTHREADS
benchmark_nthreads := $(NTHREADS)
else
# default value
benchmark_nthreads := 1 2 4 8 16
endif

ifdef CLONE_FROM_GIT
use_git := $(CLONE_FROM_GIT)
else
# default value
use_git := 1
endif

ifdef NUMPROC
parallel_flags := -j$(NUMPROC)
else
# default value: pull from the max number of hardware processes: `nproc` cmd output; ex: 8
parallel_flags := -j$(shell nproc)
endif

ifdef POSTFIX
benchmark_postfix := $(POSTFIX)
else
# default value
benchmark_postfix := $(shell hostname)
endif

ifdef RESULT_DIRNAME
results_dir := $(RESULT_DIRNAME)
else
# default value
results_dir := results/$(shell date '+%Y.%m.%d-%H%Mhrs-%Ssec')--$(benchmark_postfix)
endif

ifdef IMPLEMENTATIONS
implem_list := $(IMPLEMENTATIONS)
else
# default value
implem_list := system_default glibc tcmalloc jemalloc fast_malloc_1MiB fast_malloc_1GiB
endif




#
# Constants
#

topdir=$(shell readlink -f .)

benchmark_result_json := results.json # the suffix for the json file names
benchmark_result_png := results.png

# Source repos (required for ALL malloc implementations)
glibc_url := git://sourceware.org/git/glibc.git
tcmalloc_url := https://github.com/gperftools/gperftools.git
jemalloc_url := https://github.com/jemalloc/jemalloc.git
fast_malloc_url := git@github.com:ElectricRCAircraftGuy/fast_malloc.git
# - - - -
# Alternate download version and source if not using the git repo above
glibc_version := 2.26
glibc_alt_wget_url := https://ftpmirror.gnu.org/libc/glibc-$(glibc_version).tar.xz

# Build and install directories (required for each malloc implementation, to know where that
# implementation's `lib*.so` file will be)
glibc_build_dir := $(topdir)/glibc-build
glibc_install_dir := $(topdir)/glibc-install
tcmalloc_install_dir := $(topdir)/tcmalloc-install
jemalloc_install_dir := $(topdir)/jemalloc-install
fast_malloc_build_dir := $(topdir)/fast_malloc/build


#
# Functions
#

#
# Targets
#

.PHONY: all download build collect_results plot_results upload_results clean

all: download build collect_results plot_results


download:
	@echo "=========="
	@echo "=========="
	@echo "Downloading & updating these malloc implementations: [$(implem_list)]"

# system_default (include this for completeness)
	@echo "====="
ifeq ($(findstring system_default,$(implem_list)),system_default)
	@echo "system_default already ready"
endif

# glibc
	@echo "====="
ifeq ($(findstring glibc,$(implem_list)),glibc)
ifeq ($(use_git),1)
	@if [ ! -d glibc ]; then \
		git clone $(glibc_url); \
	else \
		echo "glibc GIT repo is already downloaded; pulling latest"; \
		cd "glibc" && git pull; \
	fi
else
	@[ ! -d glibc ] && ( wget $(glibc_alt_wget_url) && tar xvf glibc-$(glibc_version).tar.xz \
		&& mv glibc-$(glibc_version) glibc ) || echo "glibc GIT repo seems to be already there"
endif
endif

# tcmalloc
	@echo "====="
ifeq ($(findstring tcmalloc,$(implem_list)),tcmalloc)
	@if [ ! -d gperftools ]; then \
		git clone $(tcmalloc_url); \
	else \
		echo "Google perftools (tcmalloc) GIT repo is already downloaded; pulling latest"; \
		cd "gperftools" && git pull; \
	fi
endif

# jemalloc
	@echo "====="
ifeq ($(findstring jemalloc,$(implem_list)),jemalloc)
	@if [ ! -d jemalloc ]; then \
		git clone $(jemalloc_url); \
	else \
		echo "jemalloc GIT repo is already downloaded; pulling latest"; \
		cd "jemalloc" && git pull; \
	fi
endif

# fast_malloc
	@echo "====="
ifeq ($(findstring fast_malloc,$(implem_list)),fast_malloc)
	@if [ ! -d fast_malloc ]; then \
		git clone $(fast_malloc_url); \
	else \
		echo "fast_malloc GIT repo is already downloaded; pulling latest"; \
		cd "fast_malloc" && git pull; \
	fi
endif


# Individual build targets for each malloc implementation

# A couple of notes about GNU libc:
#  1) building in source dir is not supported... that's why we build in separate folder
#  2) building only benchmark utilities is not supported... that's why we build everything
$(glibc_install_dir)/lib/libc.so.6:
	@echo "Building GNU libc... go get a cup of coffee... this will take time!"
	mkdir -p $(glibc_build_dir)
	cd $(glibc_build_dir) && \
		../glibc/configure --prefix=$(glibc_install_dir) && \
		make $(parallel_flags) && \
		make bench-build $(parallel_flags) && \
		make install
	@if [ -x $(glibc_build_dir)/benchtests/bench-malloc-thread ]; then \
		echo ">>> GNU libc benchmarking utility is ready! <<<"; \
	else \
		echo ">>> ERROR: Cannot find GNU libc benchmarking utility! Cannot collect benchmark"; \
		echo "    results. <<<"; \
	fi

$(tcmalloc_install_dir)/lib/libtcmalloc.so:
	cd gperftools && \
		./autogen.sh && \
		./configure --prefix=$(tcmalloc_install_dir) && \
		make && \
		make install

$(jemalloc_install_dir)/lib/libjemalloc.so:
	cd jemalloc && \
		./autogen.sh && \
		./configure --prefix=$(jemalloc_install_dir) && \
		make && \
		( make install || true )

$(fast_malloc_build_dir)/libfast_malloc.so:
	cd fast_malloc && \
		./build_all.sh

clean:
	@echo "Removing all lib*.so target files so that 'make build' will build them again."
	rm "$(glibc_install_dir)/lib/libc.so.6"
	rm "$(tcmalloc_install_dir)/lib/libtcmalloc.so"
	rm "$(jemalloc_install_dir)/lib/libjemalloc.so"
	rm "$(fast_malloc_build_dir)/libfast_malloc.so"


build:
	@echo "=========="
	@echo "=========="
	@echo "Building these malloc implementations: [$(implem_list)], so long as their lib*.so "
	@echo "shared object files do NOT already exist. To force rebuilding, run 'make clean' first."

# glibc
ifeq ($(findstring glibc,$(implem_list)),glibc)
	@echo "====="
	@echo "glibc"
	$(MAKE) $(glibc_install_dir)/lib/libc.so.6
endif

# tcmalloc
ifeq ($(findstring tcmalloc,$(implem_list)),tcmalloc)
	@echo "====="
	@echo "tcmalloc"
	$(MAKE) $(tcmalloc_install_dir)/lib/libtcmalloc.so
endif

# jemalloc
ifeq ($(findstring jemalloc,$(implem_list)),jemalloc)
	@echo "====="
	@echo "jemalloc"
	$(MAKE) $(jemalloc_install_dir)/lib/libjemalloc.so
endif

# fast_malloc
ifeq ($(findstring fast_malloc,$(implem_list)),fast_malloc)
	@echo "====="
	@echo "fast_malloc"
	$(MAKE) $(fast_malloc_build_dir)/libfast_malloc.so
endif

# summary
	@echo "====="
	@echo "Congrats! Successfully built all malloc implementations to test,"
	@echo "  namely [$(implem_list)]."


collect_results:
	@mkdir -p $(results_dir)

	@echo "Collecting hardware information (sudo required) in $(results_dir)/hardware-inventory.txt"
	@sudo lshw -short -class memory -class processor	> $(results_dir)/hardware-inventory.txt
	@echo -n "Number of CPU cores: "					>>$(results_dir)/hardware-inventory.txt
	@grep "processor" /proc/cpuinfo | wc -l				>>$(results_dir)/hardware-inventory.txt
	# NB: you may need to install `numactl` first with `sudo apt install numactl`.
	@(which numactl >/dev/null 2>&1) && echo "NUMA information (from 'numactl -H'):" \
		>>$(results_dir)/hardware-inventory.txt
	@(which numactl >/dev/null 2>&1) && numactl -H >>$(results_dir)/hardware-inventory.txt

	@echo "Starting to collect performance benchmarks."
	./bench_collect_results.py "$(implem_list)" $(results_dir)/$(benchmark_result_json) \
		$(benchmark_nthreads)

plot_results:
	./bench_plot_results.py $(results_dir)/$(benchmark_result_png) $(results_dir)/*.json

# The following target is primarily intended to be used by the maintainer of the github project:
upload_results:
	git add -f $(results_dir)/*$(benchmark_result_json) $(results_dir)/$(benchmark_result_png) \
		$(results_dir)/hardware-inventory.txt
	git commit -m "Adding results from folder $(results_dir) to the GIT repository"
	@echo "Run 'git push' to push online your results (requires GIT repo write access)"

