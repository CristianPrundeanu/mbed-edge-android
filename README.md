# Wrapper system for building mbed-edge for Android

Before building, make sure the following are exported to the environment:
* ANDROID_HOME - root of the Android SDK, something like `/Users/<you>/Library/Android/sdk`
* ANDROID_NDK - root of the Android NDK, something like `$ANDROID_HOME/ndk-bundle`

and place `mbed_cloud_dev_credentials.c` in or around the current directory.

To build, simply type `./edge-android.sh [target_directory]` - it will check out the code and patch it for Android builds, set up the build environment, invoke cmake with all the command line arguments needed to build for an x86 Android Emulator, and finally run make and build the mbed-edge binaries.

Tested on MacOS Mojave (10.14), with the following prerequisites:
* Android SDK version 24 installed with Android Studio: https://developer.android.com/studio/
* Android NDK version r17c: https://developer.android.com/ndk/downloads/older_releases
* Java JDK version 8u181: https://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html
