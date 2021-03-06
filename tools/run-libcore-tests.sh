#!/bin/bash
#
# Copyright (C) 2014 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ ! -d libcore ]; then
  echo "Script needs to be run at the root of the android tree"
  exit 1
fi

source build/envsetup.sh >&/dev/null # for get_build_var, setpaths
setpaths # include platform prebuilt java, javac, etc in $PATH.

if [ -z "$ANDROID_PRODUCT_OUT" ] ; then
  JAVA_LIBRARIES=out/target/common/obj/JAVA_LIBRARIES
else
  JAVA_LIBRARIES=${ANDROID_PRODUCT_OUT}/../../common/obj/JAVA_LIBRARIES
fi

# "Root" (actually "system") directory on device (in the case of
# target testing).
android_root=${ART_TEST_ANDROID_ROOT:-/system}

function classes_jar_path {
  local var="$1"
  local suffix="jar"

  echo "${JAVA_LIBRARIES}/${var}_intermediates/classes.${suffix}"
}

function cparg {
  for var
  do
    printf -- "--classpath $(classes_jar_path "$var") ";
  done
}

function boot_classpath_arg {
  local dir="$1"
  local suffix="$2"
  shift 2
  printf -- "--vm-arg -Xbootclasspath"
  for var
  do
    printf -- ":${dir}/${var}${suffix}.jar";
  done
}

# Note: This must start with the CORE_IMG_JARS in Android.common_path.mk
# because that's what we use for compiling the core.art image.
# It may contain additional modules from TEST_CORE_JARS.
BOOT_CLASSPATH_JARS="core-oj core-libart core-icu4j okhttp bouncycastle apache-xml conscrypt"

DEPS="core-tests jsr166-tests mockito-target"

for lib in $DEPS
do
  if [[ ! -f "$(classes_jar_path "$lib")" ]]; then
    echo "${lib} is missing. Before running, you must run art/tools/buildbot-build.sh"
    exit 1
  fi
done

expectations="--expectations art/tools/libcore_failures.txt"

emulator="no"
if [ "$ANDROID_SERIAL" = "emulator-5554" ]; then
  emulator="yes"
fi

# Use JIT compiling by default.
use_jit=true

# Packages that currently work correctly with the expectation files.
working_packages=("libcore.android.system"
                  "libcore.build"
                  "libcore.dalvik.system"
                  "libcore.java.awt"
                  "libcore.java.lang"
                  "libcore.java.math"
                  "libcore.java.text"
                  "libcore.java.util"
                  "libcore.javax.crypto"
                  "libcore.javax.net"
                  "libcore.javax.security"
                  "libcore.javax.sql"
                  "libcore.javax.xml"
                  "libcore.libcore.internal"
                  "libcore.libcore.io"
                  "libcore.libcore.net"
                  "libcore.libcore.reflect"
                  "libcore.libcore.util"
                  "libcore.libcore.timezone"
                  "libcore.sun.invoke"
                  "libcore.sun.net"
                  "libcore.sun.misc"
                  "libcore.sun.security"
                  "libcore.sun.util"
                  "libcore.xml"
                  "org.apache.harmony.annotation"
                  "org.apache.harmony.crypto"
                  "org.apache.harmony.luni"
                  "org.apache.harmony.nio"
                  "org.apache.harmony.regex"
                  "org.apache.harmony.testframework"
                  "org.apache.harmony.tests.java.io"
                  "org.apache.harmony.tests.java.lang"
                  "org.apache.harmony.tests.java.math"
                  "org.apache.harmony.tests.java.util"
                  "org.apache.harmony.tests.java.text"
                  "org.apache.harmony.tests.javax.security"
                  "tests.java.lang.String"
                  "jsr166")

# List of packages we could run, but don't have rights to revert
# changes in case of failures.
# "org.apache.harmony.security"

vogar_args=$@
gcstress=false
debug=false

# Run tests that use the getrandom() syscall? (Requires Linux 3.17+).
getrandom=true

# Don't use device mode by default.
device_mode=false

while true; do
  if [[ "$1" == "--mode=device" ]]; then
    device_mode=true
    # Remove the --mode=device from the arguments and replace it with --mode=device_testdex
    vogar_args=${vogar_args/$1}
    vogar_args="$vogar_args --mode=device_testdex"
    vogar_args="$vogar_args --vm-arg -Ximage:/data/art-test/core.art"
    vogar_args="$vogar_args $(boot_classpath_arg /system/framework -testdex $BOOT_CLASSPATH_JARS)"
    shift
  elif [[ "$1" == "--mode=host" ]]; then
    # We explicitly give a wrong path for the image, to ensure vogar
    # will create a boot image with the default compiler. Note that
    # giving an existing image on host does not work because of
    # classpath/resources differences when compiling the boot image.
    vogar_args="$vogar_args --vm-arg -Ximage:/non/existent/vogar.art"
    shift
  elif [[ "$1" == "--no-jit" ]]; then
    # Remove the --no-jit from the arguments.
    vogar_args=${vogar_args/$1}
    use_jit=false
    shift
  elif [[ "$1" == "--debug" ]]; then
    # Remove the --debug from the arguments.
    vogar_args=${vogar_args/$1}
    vogar_args="$vogar_args --vm-arg -XXlib:libartd.so --vm-arg -XX:SlowDebug=true"
    debug=true
    shift
  elif [[ "$1" == "-Xgc:gcstress" ]]; then
    gcstress=true
    shift
  elif [[ "$1" == "--no-getrandom" ]]; then
    # Remove the option from Vogar arguments.
    vogar_args=${vogar_args/$1}
    getrandom=false
    shift
  elif [[ "$1" == "" ]]; then
    break
  else
    shift
  fi
done

if $device_mode; then
  # Honor environment variable ART_TEST_CHROOT.
  if [[ -n "$ART_TEST_CHROOT" ]]; then
    # Set Vogar's `--chroot` option.
    vogar_args="$vogar_args --chroot $ART_TEST_CHROOT"
    vogar_args="$vogar_args --device-dir=/tmp"
  else
    # When not using a chroot on device, set Vogar's work directory to
    # /data/local/tmp.
    vogar_args="$vogar_args --device-dir=/data/local/tmp"
  fi
  vogar_args="$vogar_args --vm-command=$android_root/bin/art"
fi

# Increase the timeout, as vogar cannot set individual test
# timeout when being asked to run packages, and some tests go above
# the default timeout.
if $gcstress && $debug && $device_mode; then
  vogar_args="$vogar_args --timeout 1440"
elif $gcstress && $device_mode; then
  vogar_args="$vogar_args --timeout 900"
else
  vogar_args="$vogar_args --timeout 480"
fi

# set the toolchain to use.
vogar_args="$vogar_args --toolchain d8 --language CUR"

# JIT settings.
if $use_jit; then
  vogar_args="$vogar_args --vm-arg -Xcompiler-option --vm-arg --compiler-filter=quicken"
fi
vogar_args="$vogar_args --vm-arg -Xusejit:$use_jit"

# gcstress may lead to timeouts, so we need dedicated expectations files for it.
if $gcstress; then
  expectations="$expectations --expectations art/tools/libcore_gcstress_failures.txt"
  if $debug; then
    expectations="$expectations --expectations art/tools/libcore_gcstress_debug_failures.txt"
  fi
else
  # We only run this package when not under gcstress as it can cause timeouts. See b/78228743.
  working_packages+=("libcore.libcore.icu")
fi

if $getrandom; then :; else
  # Ignore failures in tests that use the getrandom() syscall (which requires
  # Linux 3.17+). This is needed on fugu (Nexus Player) devices, where the
  # kernel is Linux 3.10.
  expectations="$expectations --expectations art/tools/libcore_no_getrandom_failures.txt"
fi

# Run the tests using vogar.
echo "Running tests for the following test packages:"
echo ${working_packages[@]} | tr " " "\n"

cmd="vogar $vogar_args $expectations $(cparg $DEPS) ${working_packages[@]}"
echo "Running $cmd"
eval $cmd
