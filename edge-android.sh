#!/bin/bash

# Tested for: mbed edge commit 101f838 (tag: 0.5.2)
EDGE_HEAD=101f838
# !Tested for: mbed edge commit cd967d0 (tag: 0.6.0)
#EDGE_HEAD=cd967d0

MAINDIR="${1:-mbed-edge}"
CREDDIR="$(pwd)"
REPO_EDGE='https://github.com/ARMmbed/mbed-edge'
CREDENTIALS_FILE='mbed_cloud_dev_credentials.c'
VERBOSE=0

function error_out() {
    echo "$*"
    exit 1
}

#####################################################################
# PREFLIGHT CHECKS

function preflight_checks() {
    [ -d "$ANDROID_HOME" ] || error_out "Please define ANDROID_HOME in your environment"
    echo "ANDROID_HOME is $ANDROID_HOME"
    [ -d "$ANDROID_NDK" ] || error_out "Please define ANDROID_NDK in your environment"
    echo "ANDROID_NDK is $ANDROID_NDK"
    [ -f "$CREDDIR/$CREDENTIALS_FILE" ] || {
        CREDENTIALS_FILE="$(find .. -maxdepth 3 -name mbed_cloud_dev_credentials.c | head -1)"
        [ -f "$CREDDIR/$CREDENTIALS_FILE" ] || error_out "Can't locate file: $CREDENTIALS_FILE"
    }
    echo "Credentials file is $CREDDIR/$CREDENTIALS_FILE"
    [ -d "$MAINDIR" ] && error_out "Target directory already exists: $MAINDIR"
    echo "Setting environment up under $MAINDIR"

    # Under Ubuntu, this needs to be run:
    #sudo apt-get install libc6-dev libmosquitto-dev mosquitto-clients build-essential cmake git
    # On a Mac:
    #brew install cmake git

    # TODO: make sure all needed binaries exist
}

#####################################################################
# BUILD ENVIRONMENT SETUP

function setup_repos() {
    echo '**** Cloning repos ****'
    git clone "$REPO_EDGE"  "$MAINDIR" || error_out "Could not clone $REPO_EDGE to $MAINDIR"
    cd "$MAINDIR"
    git checkout $EDGE_HEAD || error out "Can't find commit $EDGE_HEAD"
    git submodule init || error_out "git submodule init failed"
    git submodule update || error_out "git submodule update failed"
}

function setup_creds() {
    cp "$CREDDIR/$CREDENTIALS_FILE" "config/" || error_out "Could not copy credentials file"
}

function setup_patches() {
    echo '**** Patching libevent ****'
    cd lib/libevent/libevent 2>/dev/null || cd lib/libevent
    # patch libevent to work properly with arch4random_addrandom
    git cherry-pick 6541168d || error_out "Patching failed, please fix this script"
    # NOTE that only tabs are stripped from the beginning of here-document lines!
    git apply <<-"EOT" || error_out "Patching failed"
	diff --git a/evutil.c b/evutil.c
	index 1e8ef7bd..1a3b2003 100644
	--- a/evutil.c
	+++ b/evutil.c
	@@ -42,6 +42,10 @@
	 #include <iphlpapi.h>
	 #endif
	 
	+#if defined(ANDROID) || defined(__ANDROID__)
	+#define __USE_GNU
	+#endif
	+
	 #include <sys/types.h>
	 #ifdef EVENT__HAVE_SYS_SOCKET_H
	 #include <sys/socket.h>
	EOT
    cd -

    echo '**** Patching libwebsockets ****'
    cd lib/libwebsockets/libwebsockets 2>/dev/null || cd lib/libwebsockets
    git apply <<-"EOT" || error_out "Patching failed"
	diff --git a/lib/libwebsockets.h b/lib/libwebsockets.h
	index b125d1b8..bf25d7c8 100644
	--- a/lib/libwebsockets.h
	+++ b/lib/libwebsockets.h
	@@ -106,7 +106,7 @@ typedef unsigned long long lws_intptr_t;
	 #include <sys/capability.h>
	 #endif
	 
	-#if defined(__NetBSD__) || defined(__FreeBSD__) || defined(__QNX__)
	+#if defined(__NetBSD__) || defined(__FreeBSD__) || defined(__QNX__) || defined(__ANDROID__) || defined(ANDROID)
	 #include <netinet/in.h>
	 #endif
	 
	EOT
    cd -

    echo '**** Patching edge-client ****'
    # TODO: make more elegant conditional patch, so pthread and rt are still used on non-Android platforms
    sed -e 's/ pthread / /g' -e 's/ rt//g' -e 's/stdc++/c++/' -i -- edge-client/CMakeLists.txt || error_out "Patching failed"

    echo '**** Patching mbed-cloud-client ****'
    git apply <<-"EOT" || error_out "Patching failed"
	diff --git a/lib/mbed-cloud-client/factory-configurator-client/factory-configurator-client/factory-configurator-client/fcc_status.h b/lib/mbed-cloud-client/factory-configurator-client/factory-configurator-client/factory-configurator-client/fcc_status.h
	index 360b06a..1a36721 100644
	--- a/lib/mbed-cloud-client/factory-configurator-client/factory-configurator-client/factory-configurator-client/fcc_status.h
	+++ b/lib/mbed-cloud-client/factory-configurator-client/factory-configurator-client/factory-configurator-client/fcc_status.h
	@@ -66,6 +66,8 @@ extern "C" {
	         FCC_MAX_STATUS = 0x7fffffff
	 } fcc_status_e;
	 
	+fcc_status_e fcc_storage_delete();
	+
	 #ifdef __cplusplus
	 }
	 #endif
	diff --git a/lib/mbed-cloud-client/mbed-client-pal/Configs/pal_config/Linux/Linux_default.h b/lib/mbed-cloud-client/mbed-client-pal/Configs/pal_config/Linux/Linux_default.h
	index 89f5ca0..e1c3dc4 100755
	--- a/lib/mbed-cloud-client/mbed-client-pal/Configs/pal_config/Linux/Linux_default.h
	+++ b/lib/mbed-cloud-client/mbed-client-pal/Configs/pal_config/Linux/Linux_default.h
	@@ -16,6 +16,21 @@
	 
	 #ifndef PAL_DEFAULT_LINUX_CONFIGURATION_H_
	 
	+#if PAL_OS_VARIANT == Android
	+    #include <unistd.h>
	+    #include <pthread.h>
	+    #include <sys/socket.h>
	+    #include <arpa/inet.h>
	+    // fixed: sockaddr_in htons pipe2 arc4random_addrandom fcc_storage_delete
	+    // hacked: pthread_cancel pthread_sigqueue (needs SIGUSR1 handler in each thread using this API)
	+    // patches to apply: * lib/libevent: git cherry-pick 6541168d
	+    #define pthread_cancel(__thr__) pthread_kill((__thr__), SIGUSR1)
	+    #define pthread_sigqueue(__thr__, __sig__, __val__) pthread_kill((__thr__), (__sig__))
	+//    #include <signal.h>
	+//    #include <poll.h>
	+//    #include <sys/types.h>
	+//    #include <ifaddrs.h>
	+#endif
	 
	 #ifndef PAL_BOARD_SPECIFIC_CONFIG
	     #if defined(TARGET_X86_X64)
	diff --git a/lib/mbed-cloud-client/mbed-client-pal/Source/Port/Reference-Impl/OS_Specific/Linux/RTOS/pal_plat_rtos.c b/lib/mbed-cloud-client/mbed-client-pal/Source/Port/Reference-Impl/OS_Specific/Linux/RTOS/pal_plat_rtos.c
	index ab7797a..4e83d01 100644
	--- a/lib/mbed-cloud-client/mbed-client-pal/Source/Port/Reference-Impl/OS_Specific/Linux/RTOS/pal_plat_rtos.c
	+++ b/lib/mbed-cloud-client/mbed-client-pal/Source/Port/Reference-Impl/OS_Specific/Linux/RTOS/pal_plat_rtos.c
	@@ -20,7 +20,11 @@
	 #include <pthread.h>
	 #include <semaphore.h>
	 #include <signal.h>
	-#include <mqueue.h>
	+#if PAL_OS_VARIANT == Android
	+  #include <linux/mqueue.h>
	+#else
	+  #include <mqueue.h>
	+#endif
	 #include <errno.h>
	 #include <string.h>
	 #include <unistd.h>
	EOT


    # in newer revisions, pt-example may be entirely missing
    # and pt-client has already been patched officially
    [ -d pt-example ] && {
        echo '**** Patching pt-client ****'
        git apply <<-"EOT" || error_out "Patching failed"
	diff --git a/pt-client/client.c b/pt-client/client.c
	index c5e88f8..ef8ddf7 100644
	--- a/pt-client/client.c
	+++ b/pt-client/client.c
	@@ -21,6 +21,7 @@
	 #include <pthread.h>
	 
	 #include "event2/event.h"
	+#include "event2/thread.h"
	 #include "libwebsockets.h"
	 
	 #include "common/default_message_id_generator.h"
	diff --git a/pt-client/pt-client/client.h b/pt-client/pt-client/client.h
	index fec309a..2658f65 100644
	--- a/pt-client/pt-client/client.h
	+++ b/pt-client/pt-client/client.h
	@@ -22,6 +22,7 @@
	 #define CLIENT_H_
	 
	 #include "pt-client/pt_api.h"
	+struct context; // declared in pt-client/pt_api_internal.h
	 
	 /**
	  * \brief Initializes the connection structure between Mbed Cloud Edge and the connected
	EOT

        echo '**** Patching pt-example ****'
        git apply <<-"EOT" || error_out "Patching failed"
	diff --git a/pt-example/CMakeLists.txt b/pt-example/CMakeLists.txt
	index 8857793..a6ccb39 100644
	--- a/pt-example/CMakeLists.txt
	+++ b/pt-example/CMakeLists.txt
	@@ -9,5 +9,5 @@ if (NOT TARGET_GROUP STREQUAL test)
	 
	   target_include_directories (pt-example PUBLIC ${CMAKE_CURRENT_LIST_DIR})
	 
	-  target_link_libraries (pt-example pthread pt-client)
	+  target_link_libraries (pt-example pt-client)
	 endif()
	EOT
    }
}

function setup_build_files() {
    echo '**** Creating setup files ****'
    # TODO: check for conflicts before clobbering files

    cat <<-"EOT" >cmake/targets/android.cmake
	message("Building Android target")

	if(NOT DEFINED ANDROID_NDK)
	    if(NOT DEFINED ENV{ANDROID_NDK})
	        message(FATAL_ERROR "Please define ANDROID_NDK or export it from your environment.")
	    endif()
	    set(ANDROID_NDK $ENV{ANDROID_NDK})
	endif()
	if (NOT EXISTS ${ANDROID_NDK}/sysroot)
	    message(FATAL_ERROR "ANDROID_NDK is defined but missing the sysroot directory.")
	endif()
	set(CMAKE_ANDROID_NDK $ENV{ANDROID_NDK})

	set(ANDROID_PLATFORM android-24)

	# STL possible values: c++_static gnustl_static stlport_static gabi++_static (or *_shared)
	# do we need to set CMAKE_ANDROID_STL_TYPE as well?
	set(ANDROID_STL c++_shared)

	# doesn't seem to work from here, needs to be on the command line?
	set(ANDROID_NATIVE_API_LEVEL 24)

	# Android 5.0+ only support position-independent executables
	add_definitions("-fPIE")
	set(CMAKE_EXE_LINKER_FLAGS  "${CMAKE_EXE_LINKER_FLAGS} -fPIE -pie")

	set(PAL_OS_VARIANT Android)
	set(OS_BRAND Linux)
	set(MBED_CLOUD_CLIENT_DEVICE x86_x64)
	set(PAL_TARGET_DEVICE x86_x64)

	set(PAL_USER_DEFINED_CONFIGURATION "\"${CMAKE_SOURCE_DIR}/config/sotp_fs_linux.h\"")
	set(BIND_TO_ALL_INTERFACES 0)
	set(PAL_FS_MOUNT_POINT_PRIMARY "\"/data/local/tmp/edge/config\"")
	set(PAL_FS_MOUNT_POINT_SECONDARY "\"/data/local/tmp/edge/config\"")
	set(PAL_UPDATE_FIRMWARE_DIR "\"/data/local/tmp/edge/firmware\"")
	set(ARM_UC_SOCKET_TIMEOUT_MS 300000)

	set(EVENT__HAVE_WAITPID_WITH_WNOWAIT_EXITCODE 1)
	set(EVENT__HAVE_WAITPID_WITH_WNOWAIT_EXITCODE__TRYRUN_OUTPUT 1)

	if(${FIRMWARE_UPDATE})
	    set(MBED_CLOUD_CLIENT_UPDATE_STORAGE ARM_UCP_LINUX_YOCTO_RPI)
	endif()
	EOT

    cat <<-"EOT" >cmake/toolchains/gcc-linux-android-x86.cmake
	cmake_minimum_required(VERSION 3.4.1)
	MESSAGE("Building with gcc-linux-android-x86 toolchain")

	# suppress warnings resulting from poor coding
	add_definitions("-Wno-unknown-warning-option -Wno-reserved-user-defined-literal -Wno-unused-value -Wno-typedef-redefinition")
	add_definitions("-Wno-unused-but-set-variable -Wno-unused-variable -Wno-unused-function -Wno-sign-compare -Wno-write-strings -Wno-format -Wno-missing-braces -Wno-return-type")
	set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-pointer-sign")
	set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-reorder")

	set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fpic -std=gnu99" CACHE STRING "" FORCE)
	#set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-c++14-compat -frtti -fexceptions" CACHE STRING "" FORCE)
	set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-c++14-compat" CACHE STRING "" FORCE)
	set (CMAKE_EXPORT_COMPILE_COMMANDS on)
	EOT

    cat <<-"EOT" >configure.sh
	#!/bin/bash

	mkdir -p $(dirname "$0")/build
	cd $(dirname "$0")/build

	# meaningful values for ANDROID_ABI:
	#    armeabi-v7a - use this for real non-ancient phones
	#    x86 - use this for the Mac Android Emulator
	#    x86_64
	#    arm64-v8a
	#    mips - unsupported as of NDK r17
	ANDROID_ABI=x86

	# possible values for ANDROID_TOOLCHAIN:
	#    gcc - deprecated in more recent Android versions but required for Qt <= 5.11
	#    clang
	ANDROID_TOOLCHAIN=gcc

	# other parameters specific to the mbed edge build
	EDGE_PARAMS="-DTARGET_TOOLCHAIN=gcc-linux-android-x86 -DTARGET_DEVICE=Android"
	EDGE_PARAMS+=" -DDEVELOPER_MODE=ON -DFIRMWARE_UPDATE=OFF -DTRACE_LEVEL=DEBUG"

	set -x
	cmake "-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
	      "-DANDROID_ABI=$ANDROID_ABI" \
	      "-DANDROID_TOOLCHAIN=$ANDROID_TOOLCHAIN" \
	      "-DANDROID_NATIVE_API_LEVEL=24" \
	      $EDGE_PARAMS \
	      ..
	EOT
    chmod +x configure.sh

    cat <<-"EOT" >cmake/toolchains/gcc-linux-android-arm.cmake
	EOT
    # TODO: add armv7 toolchain file content
}

#####################################################################
# COMPILE AND LINK

function make_build()
{
    cd "$MAINDIR"
    rm -rf build
    ./configure.sh
    cd build

    local MK_VERBOSE
    [ "$VERBOSE" -eq 1 ] && MK_VERBOSE="VERBOSE=1"
    make $MK_VERBOSE 2>&1 | tee build.log
}

#####################################################################
# MAIN

# TODO: implement command line args for selective functions
# TODO: add verbose flag
# TODO: add arg for credentials file location

[ "$1" = "-h" -o "$1" = "--help" -o "$1" = "-help" ] && error_out "Usage: $0 [build_dir]"

preflight_checks

setup_repos
setup_creds
setup_patches
setup_build_files

make_build
