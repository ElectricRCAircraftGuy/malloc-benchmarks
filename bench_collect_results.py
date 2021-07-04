#!/usr/bin/python3
"""Generate benchmarking results in JSON form, using GNU libc benchmarking utility;
different allocators are injected into that utility by using LD_PRELOAD trick.
"""
import sys
import os
import json
import subprocess

#
# Constants
#

internal_benchmark_util = 'glibc-build/benchtests/bench-malloc-thread'

glibc_install_dir = 'glibc-install'

# Specify the 'lib*.so' shared object libraries we will need to preload via the `LD_PRELOAD` trick
# for each malloc implementation
# key:   malloc implementation name
# value: the path to the 'lib*.so' shared object library or libraries to preload
impl_preload_libs = {
    'system_default':'',
    'glibc': '',
    
    # To test tcmalloc and jemalloc implementations we simply use the LD_PRELOAD trick:
    'tcmalloc': 'tcmalloc-install/lib/libtcmalloc.so',
    'jemalloc': 'jemalloc-install/lib/libjemalloc.so',

    # We will use the LD_PRELOAD trick for fast_malloc too
    'fast_malloc_1MiB': 'fast_malloc/build/libfast_malloc_1MiB.so',
    'fast_malloc_1GiB': 'fast_malloc/build/libfast_malloc_1GiB.so',
}

# to successfully preload the tcmalloc,jemalloc libs we will also need to preload the C++ standard
# lib and gcc_s lib:
preload_required_libs= [ 'libstdc++.so.6', 'libgcc_s.so.1' ]
preload_required_libs_fullpaths = []

# Specify exactly how to call the benchmark utility for each malloc implementation
# key:   malloc implementation name
# value: the exact call to the internal benchmark utility
benchmark_util = {
    'system_default': internal_benchmark_util,
    
    # to test the latest GNU libc implementation downloaded and compiled locally we use another
    # trick: we ask the dynamic linker of the just-built GNU libc to run the benchmarking utility
    # using the new GNU libc dynamic libs:
    'glibc': (glibc_install_dir + '/lib/ld-linux-x86-64.so.2 --library-path ' + glibc_install_dir +
             '/lib ' + internal_benchmark_util),
    
    'tcmalloc': internal_benchmark_util,
    'jemalloc': internal_benchmark_util,

    'fast_malloc_1MiB': internal_benchmark_util,
    'fast_malloc_1GiB': internal_benchmark_util,
}

def find(name, paths):
    for path in paths:
        #print("Searching into: ", path)
        for root, dirs, files in os.walk(path, followlinks=False):
            if name in files:
                return os.path.join(root, name)
    return ""

def find_no_symlink(name, paths):
    matching_filepath = find(name, paths)
    if len(matching_filepath)==0:
        return ''
    
    # is the result a symlink?
    while os.path.islink(matching_filepath):
        result = os.readlink(matching_filepath)
        matching_filepath = os.path.join(os.path.dirname(matching_filepath), result)
    return matching_filepath

def check_requirements():
    global preload_required_libs_fullpaths, impl_preload_libs, benchmark_util
    
#     for util in benchmark_util.values():
#         if not os.path.isfile(util):
#             print("Could not find required benchmarking utility {}".format(util))
#             sys.exit(2)
#         print("Found required benchmarking utility {}".format(util))
    if not os.path.isfile(internal_benchmark_util):
        print("Could not find required benchmarking utility {}".format(internal_benchmark_util))
        sys.exit(2)
    print("Found required benchmarking utility {}".format(internal_benchmark_util))

    for preloadlib in impl_preload_libs.values():
        if len(preloadlib)>0:
            if not os.path.isfile(preloadlib):
                print("Could not find required lib {}".format(preloadlib))
                sys.exit(2)
            print("Found required lib {}".format(preloadlib))

    for reqlib in preload_required_libs:
        full_path = find_no_symlink(reqlib, ['/usr/lib', '/lib', '/lib64'])
        if len(full_path)==0:
            print("Could not find required shared library {}".format(reqlib))
            sys.exit(2)
        print("Found required lib {}".format(full_path))
        preload_required_libs_fullpaths.append(full_path)

def run_benchmark(outfile, thread_values, impl_name):
    global preload_required_libs_fullpaths, impl_preload_libs
    
    if impl_name not in impl_preload_libs:
        print("Unknown settings required for testing implementation {}".format(impl_name))
        sys.exit(3)
    
    of = open(outfile, 'w')
    of.write('[')
    
    success = 0
    last_nthreads = thread_values[len(thread_values)-1]
    bm = {}
    for nthreads in thread_values:
        # run the external benchmark utility with the LD_PRELOAD trick

        try:
            # 1. Set the `LD_PRELOAD` environment variable

            os.environ["LD_PRELOAD"] = impl_preload_libs[impl_name]

            # The `tcmalloc` and `jemalloc` shared libs require some additional C++ libs, so let's
            # load those too if necessary.
            if impl_name in ["tcmalloc", "jemalloc"]:
                #print("preload_required_libs_fullpaths is:", preload_required_libs_fullpaths)
                for lib in preload_required_libs_fullpaths:
                    os.environ["LD_PRELOAD"] = os.environ["LD_PRELOAD"] + ':' + lib
                    
            utility_fname = benchmark_util[impl_name]
                    
            cmd = "{} {} | tee /tmp/benchmark-output".format(utility_fname, nthreads)
            full_cmd = "LD_PRELOAD='{}' {}".format(os.environ["LD_PRELOAD"], cmd)

            print("Running this benchmark cmd for nthreads={}:".format(nthreads))
            print("  {}".format(full_cmd))

            # 2. Call the benchmark cmd

            # the subprocess.check_output() method does not seem to work fine when launching
            # the ld-linux-x86-64.so.2 with --library-path
            #stdout = subprocess.check_output([utility_fname, nthreads])
            os.system(cmd)
            stdout = open('/tmp/benchmark-output', 'r').read()

            # produce valid JSON output:
            of.write(stdout)
            if nthreads != last_nthreads:
                of.write(',')
            success += 1
            
        except OSError as ex:
            print("Failed running malloc benchmarking utility: {}. Skipping.".format(ex))

    of.write(']\n')
    return success

def main(args):
    """Program Entry Point
    """
    if len(args) < 2:
        print('Usage: %s <implementation-list> <output filename postfix> <num threads test1> <num threads test2> ...' % sys.argv[0])
        sys.exit(os.EX_USAGE)

    # parse args
    implementations_to_test = args[0].split()
    outfile_path_prefix, outfile_postfix = os.path.split(args[1])
    thread_values = args[2:]
    
    check_requirements()
    
    success = 0
    for implementation in implementations_to_test:
        if implementation not in impl_preload_libs:
            print(("Unknown settings required for testing implementation \"{}\". Update this " +
                   "python script to know how to test this implementation too.").format(
                   implementation))
            sys.exit(3)

        outfile = os.path.join(outfile_path_prefix, implementation + '-' + outfile_postfix)
        print("----------------------------------------------------------------------------------------------")
        print("Testing implementation '{}'.\nSaving results into '{}'".format(implementation, outfile))
        
        print("Will run tests for {} different numbers of threads.".format(len(thread_values)))
        success = success + run_benchmark(outfile, thread_values, implementation)

    print("----------------------------------------------------------------------------------------------")
    return success

if __name__ == '__main__':
    success = main(sys.argv[1:])
    if success==0:
        sys.exit(1)
        
