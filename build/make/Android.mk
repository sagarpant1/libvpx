##
##  Copyright (c) 2012 The WebM project authors. All Rights Reserved.
##
##  Use of this source code is governed by a BSD-style license
##  that can be found in the LICENSE file in the root of the source
##  tree. An additional intellectual property rights grant can be found
##  in the file PATENTS.  All contributing project authors may
##  be found in the AUTHORS file in the root of the source tree.
##

#
# This file is to be used for compiling libvpx for Android using the NDK.
# In an Android project place a libvpx checkout in the jni directory.
# Run the configure script from the jni directory.  Base libvpx
# encoder/decoder configuration will look similar to:
# ./libvpx/configure --target=armv7-android-gcc --disable-examples \
#                    --sdk-path=/opt/android-ndk-r6b/
#
# When targeting Android, realtime-only is enabled by default.  This can
# be overridden by adding the command line flag:
#  --disable-realtime-only
#
# This will create .mk files that contain variables that contain the
# source files to compile.
#
# Place an Android.mk file in the jni directory that references the
# Android.mk file in the libvpx directory:
# LOCAL_PATH := $(call my-dir)
# include $(CLEAR_VARS)
# include jni/libvpx/build/make/Android.mk
#
# There are currently two TARGET_ARCH_ABI targets for ARM.
# armeabi and armeabi-v7a.  armeabi-v7a is selected by creating an
# Application.mk in the jni directory that contains:
# APP_ABI := armeabi-v7a
#
# By default libvpx will detect at runtime the existance of NEON extension.
# For this we import the 'cpufeatures' module from the NDK sources.
# libvpx can also be configured without this runtime detection method.
# Configuring with --disable-runtime-cpu-detect will assume presence of NEON.
# Configuring with --disable-runtime-cpu-detect --disable-neon \
#     --disable-neon-asm
# will remove any NEON dependency.

# To change to building armeabi, run ./libvpx/configure again, but with
# --target=armv6-android-gcc and modify the Application.mk file to
# set APP_ABI := armeabi
#
# Running ndk-build will build libvpx and include it in your project.
#

CONFIG_DIR := $(LOCAL_PATH)/
LIBVPX_PATH := $(LOCAL_PATH)/libvpx
ASM_CNV_PATH_LOCAL := $(TARGET_ARCH_ABI)/ads2gas
ASM_CNV_PATH := $(LOCAL_PATH)/$(ASM_CNV_PATH_LOCAL)

# Use the makefiles generated by upstream configure to determine which files to
# build. Also set any architecture-specific flags.
ifeq ($(TARGET_ARCH_ABI),armeabi-v7a)
  include $(CONFIG_DIR)libs-armv7-android-gcc.mk
  LOCAL_ARM_MODE := arm
else ifeq  ($(TARGET_ARCH_ABI),armeabi)
  include $(CONFIG_DIR)libs-armv6-android-gcc.mk
  LOCAL_ARM_MODE := arm
else ifeq  ($(TARGET_ARCH_ABI),arm64-v8a)
  include $(CONFIG_DIR)libs-armv8-android-gcc.mk
  LOCAL_ARM_MODE := arm
else ifeq ($(TARGET_ARCH_ABI),x86)
  include $(CONFIG_DIR)libs-x86-android-gcc.mk
else ifeq ($(TARGET_ARCH_ABI),x86_64)
  include $(CONFIG_DIR)libs-x86_64-android-gcc.mk
else ifeq ($(TARGET_ARCH_ABI),mips)
  include $(CONFIG_DIR)libs-mips-android-gcc.mk
else
  $(error Not a supported TARGET_ARCH_ABI: $(TARGET_ARCH_ABI))
endif

# Rule that is normally in Makefile created by libvpx
# configure.  Used to filter out source files based on configuration.
enabled=$(filter-out $($(1)-no),$($(1)-yes))

# Override the relative path that is defined by the libvpx
# configure process
SRC_PATH_BARE := $(LIBVPX_PATH)

# Include the list of files to be built
include $(LIBVPX_PATH)/libs.mk

# Optimise the code. May want to revisit this setting in the future.
LOCAL_CFLAGS := -O3

# For x86, include the source code in the search path so it will find files
# like x86inc.asm and x86_abi_support.asm
LOCAL_ASMFLAGS := -I$(LIBVPX_PATH)

.PRECIOUS: %.asm.s
$(ASM_CNV_PATH)/libvpx/%.asm.s: $(LIBVPX_PATH)/%.asm
	@mkdir -p $(dir $@)
	@$(CONFIG_DIR)$(ASM_CONVERSION) <$< > $@

# For building *_rtcd.h, which have rules in libs.mk
TGT_ISA:=$(word 1, $(subst -, ,$(TOOLCHAIN)))
target := libs

LOCAL_SRC_FILES += vpx_config.c

# Remove duplicate entries
CODEC_SRCS_UNIQUE = $(sort $(CODEC_SRCS))

# Pull out C files.  vpx_config.c is in the immediate directory and
# so it does not need libvpx/ prefixed like the rest of the source files.
# The neon files with intrinsics need to have .neon appended so the proper
# flags are applied.
CODEC_SRCS_C = $(filter %.c, $(CODEC_SRCS_UNIQUE))
LOCAL_NEON_SRCS_C = $(filter %_neon.c, $(CODEC_SRCS_C))
LOCAL_CODEC_SRCS_C = $(filter-out vpx_config.c %_neon.c, $(CODEC_SRCS_C))

LOCAL_SRC_FILES += $(foreach file, $(LOCAL_CODEC_SRCS_C), libvpx/$(file))
ifeq ($(TARGET_ARCH_ABI),armeabi-v7a)
  LOCAL_SRC_FILES += $(foreach file, $(LOCAL_NEON_SRCS_C), libvpx/$(file).neon)
else # If there are neon sources then we are building for arm64 and do not need to specify .neon
  LOCAL_SRC_FILES += $(foreach file, $(LOCAL_NEON_SRCS_C), libvpx/$(file))
endif

# Pull out assembly files, splitting NEON from the rest.  This is
# done to specify that the NEON assembly files use NEON assembler flags.
# x86 assembly matches %.asm, arm matches %.asm.s

# x86:

CODEC_SRCS_ASM_X86 = $(filter %.asm, $(CODEC_SRCS_UNIQUE))
LOCAL_SRC_FILES += $(foreach file, $(CODEC_SRCS_ASM_X86), libvpx/$(file))

# arm:
CODEC_SRCS_ASM_ARM_ALL = $(filter %.asm.s, $(CODEC_SRCS_UNIQUE))
CODEC_SRCS_ASM_ARM = $(foreach v, \
                     $(CODEC_SRCS_ASM_ARM_ALL), \
                     $(if $(findstring neon,$(v)),,$(v)))
CODEC_SRCS_ASM_ADS2GAS = $(patsubst %.s, \
                         $(ASM_CNV_PATH_LOCAL)/libvpx/%.s, \
                         $(CODEC_SRCS_ASM_ARM))
LOCAL_SRC_FILES += $(CODEC_SRCS_ASM_ADS2GAS)

ifeq ($(TARGET_ARCH_ABI),armeabi-v7a)
  CODEC_SRCS_ASM_NEON = $(foreach v, \
                        $(CODEC_SRCS_ASM_ARM_ALL),\
                        $(if $(findstring neon,$(v)),$(v),))
  CODEC_SRCS_ASM_NEON_ADS2GAS = $(patsubst %.s, \
                                $(ASM_CNV_PATH_LOCAL)/libvpx/%.s, \
                                $(CODEC_SRCS_ASM_NEON))
  LOCAL_SRC_FILES += $(patsubst %.s, \
                     %.s.neon, \
                     $(CODEC_SRCS_ASM_NEON_ADS2GAS))
endif

LOCAL_CFLAGS += \
    -DHAVE_CONFIG_H=vpx_config.h \
    -I$(LIBVPX_PATH) \
    -I$(ASM_CNV_PATH)

LOCAL_MODULE := libvpx

ifeq ($(CONFIG_RUNTIME_CPU_DETECT),yes)
  LOCAL_STATIC_LIBRARIES := cpufeatures
endif

# Add a dependency to force generation of the RTCD files.
define rtcd_dep_template
ifeq ($(CONFIG_VP8), yes)
$(foreach file, $(LOCAL_SRC_FILES), $(LOCAL_PATH)/$(file)): vp8_rtcd.h
endif
ifeq ($(CONFIG_VP9), yes)
$(foreach file, $(LOCAL_SRC_FILES), $(LOCAL_PATH)/$(file)): vp9_rtcd.h
endif
$(foreach file, $(LOCAL_SRC_FILES), $(LOCAL_PATH)/$(file)): vpx_scale_rtcd.h
$(foreach file, $(LOCAL_SRC_FILES), $(LOCAL_PATH)/$(file)): vpx_dsp_rtcd.h

ifeq ($(TARGET_ARCH_ABI),x86)
$(foreach file, $(LOCAL_SRC_FILES), $(LOCAL_PATH)/$(file)): vpx_config.asm
endif
endef

$(eval $(call rtcd_dep_template))

.PHONY: clean
clean:
	@echo "Clean: ads2gas files [$(TARGET_ARCH_ABI)]"
	@$(RM) $(CODEC_SRCS_ASM_ADS2GAS) $(CODEC_SRCS_ASM_NEON_ADS2GAS)
	@$(RM) -r $(ASM_CNV_PATH)
	@$(RM) $(CLEAN-OBJS)

ifeq ($(ENABLE_SHARED),1)
  include $(BUILD_SHARED_LIBRARY)
else
  include $(BUILD_STATIC_LIBRARY)
endif

ifeq ($(CONFIG_RUNTIME_CPU_DETECT),yes)
$(call import-module,cpufeatures)
endif
