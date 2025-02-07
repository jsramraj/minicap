#!/usr/bin/env bash

# Fail on error, verbose output
set -exo pipefail

# Build project
# experimental/gradlew -p experimental assembleDebug
# ndk-build NDK_DEBUG=1 1>&2

while getopts ":a:" opt; do
  case $opt in
    a) serialId="$OPTARG"
    ;;
    p) p_out="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac

  case $OPTARG in
    -*) echo "Option $opt needs a valid argument"
    ;;
  esac
done
printf "SerialId is %s\n" "$serialId"

# Figure out which ABI and SDK the device has
abi=$(adb -s $serialId shell getprop ro.product.cpu.abi | tr -d '\r')
sdk=$(adb -s $serialId shell getprop ro.build.version.sdk | tr -d '\r')
pre=$(adb -s $serialId shell getprop ro.build.version.preview_sdk | tr -d '\r')
rel=$(adb -s $serialId shell getprop ro.build.version.release | tr -d '\r')

if [[ -n "$pre" && "$pre" > "0" ]]; then
  sdk=$(($sdk + 1))
fi

# PIE is only supported since SDK 16
if (($sdk >= 16)); then
  bin=minicap
else
  bin=minicap-nopie
fi

apk="app_process /system/bin io.devicefarmer.minicap.Main"

args=
if [ "$1" = "autosize" ]; then
  set +o pipefail
  size=$(adb -s $serialId shell dumpsys window | grep -Eo 'init=[0-9]+x[0-9]+' | head -1 | cut -d= -f 2)
  if [ "$size" = "" ]; then
    w=$(adb -s $serialId shell dumpsys window | grep -Eo 'DisplayWidth=[0-9]+' | head -1 | cut -d= -f 2)
    h=$(adb -s $serialId shell dumpsys window | grep -Eo 'DisplayHeight=[0-9]+' | head -1 | cut -d= -f 2)
    size="${w}x${h}"
  fi
  args="-P $size@$size/0"
  set -o pipefail
  shift
fi

# Create a directory for our resources
dir=/data/local/tmp/minicap-devel
# Keep compatible with older devices that don't have `mkdir -p`.
adb -s $serialId shell "mkdir $dir 2>/dev/null || true"

# Upload the binary
adb -s $serialId push scripts/libs/$abi/$bin $dir

# Upload the shared library
if [ -e jni/minicap-shared/aosp/libs/android-$rel/$abi/minicap.so ]; then
  adb -s $serialId push jni/minicap-shared/aosp/libs/android-$rel/$abi/minicap.so $dir
  adb -s $serialId shell LD_LIBRARY_PATH=$dir $dir/$bin $args "$@"
else
  if [ -e jni/minicap-shared/aosp/libs/android-$sdk/$abi/minicap.so ]; then
    adb -s $serialId push jni/minicap-shared/aosp/libs/android-$sdk/$abi/minicap.so $dir
    adb -s $serialId shell LD_LIBRARY_PATH=$dir $dir/$bin $args "$@"
  else
    adb -s $serialId push scripts/experimental/app/build/outputs/apk/debug/minicap-debug.apk $dir
    adb -s $serialId shell CLASSPATH=$dir/minicap-debug.apk $apk $args "$@"
  fi
fi

# Clean up
adb -s $serialId shell rm -r $dir
