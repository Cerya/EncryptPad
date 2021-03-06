# -*- Makefile -*-
################################################################################
#
# Author: Andy Rushton
# Copyright: (c) Andy Rushton, 1999 onwards
# License:   BSD License, see docs/license.html
#
# Part of the generic makefile system - rules for building a project
# For use in gcc.mak
#
################################################################################

################################################################################
# setup variations in default compiler flags

ifeq ($(PLATFORM),SOLARIS)
# have to explicitly pull in the socket library
LOADLIBES += -lsocket
endif

ifeq ($(PLATFORM),NETBSD)
# have to explicitly state that the maths library should be included
LOADLIBES += -lm
endif

ifeq ($(BUILD),LINUX-alpha)
# enable IEEE-standard floating point
CPPFLAGS += -mieee
endif

ifeq ($(PLATFORM),CYGWIN)
# gcc handling of DLLs on Windows
LDFLAGS += -Wl,--enable-auto-import
endif

ifeq ($(PLATFORM),MINGW)
# need to explicitly add the Windows sockets 2 library
LOADLIBES += -lWs2_32
# gcc handling of DLLs on Windows
LDFLAGS += -Wl,--enable-auto-import
endif

ifeq ($(STATIC),on)
# switch on static linking with C/C++ runtimes
LDFLAGS += -static-libgcc -static-libstdc++
else
LOADLIBES += -lstdc++
endif

ifeq ($(PLATFORM),GNULINUX)
# Issue found on Fedora. All other components used fPIC.
CPPFLAGS += -fPIC
endif

################################################################################
# Configure build variant
# there are four different build variants:
#   debug - for internal development (default)
#   release - for shipping to customers (switched on by environment variable RELEASE=on)
#   gprof - for performance profiling (switched on by environment variable GPROF=on)
#   gcov - for code coverage (switched on by environment variable GCOV=on)

# common options for all variant builds for compile/link
CPPFLAGS  += -I. -D$(PLATFORM)
CFLAGS    += -funsigned-char
CXXFLAGS  += -ftemplate-depth-50 -funsigned-char
LDFLAGS   +=


ifeq ($(RELEASE),on)
# release variant
CPPFLAGS += -DNDEBUG
CFLAGS   += -O3
CXXFLAGS += -O3
ifneq ($(PLATFORM),MACOS)
# the condition was added by evpo. -s is deprecated but is still used on clang. It causes an internal ld error "atom not found in symbolIndex"
# TODO: temporary to enable debug symbols
# LDFLAGS  += -s
endif
else # RELEASE off
ifeq ($(GPROF),on)
# gprof variant
CPPFLAGS += -DNDEBUG
CFLAGS   += -O3 -pg
CXXFLAGS += -O3 -pg
LDFLAGS  += -pg
else # GPROF off
ifeq ($(GCOV),on)
# gcov variant
CPPFLAGS += 
CFLAGS   += -O0 -fprofile-arcs -ftest-coverage
CXXFLAGS += -O0 -fprofile-arcs -ftest-coverage
LDFLAGS  += -fprofile-arcs -lgcov
else # GCOV off
# debug variant
CPPFLAGS +=
CFLAGS   += -g
CXXFLAGS += -g
LDFLAGS  +=
endif # GCOV
endif # GPROF
endif # RELEASE

BUILD_TYPE=dynamic
ifeq ($(STATIC),on)
BUILD_TYPE=static
endif

################################################################################
# Unicode support
# use the option UNICODE=on to enable Unicode support
# this defines the pre-processor directives that switch on Unicode support in the headers
# Some libraries require directive UNICODE and others require _UNICODE, so define both
# Notes:
# - MinGW does not support wide I/O streams
# - Cygwin does not support wide strings or streams

ifeq ($(UNICODE),on)
CPPFLAGS += -DUNICODE -D_UNICODE
endif

################################################################################
# Resource compiler - make this Windows only

ifeq ($(WINDOWS),on)
#RC := "windres"
endif

################################################################################
# verbose option causes compiler/linker to be verbose

ifeq ($(VERBOSE),on)
CFLAGS    += -v
CXXFLAGS  += -v
LDFLAGS   += -v
RCFLAGS   += -v
endif

################################################################################
# now start generating the build structure

# this adapts the make to find all .cpp files so they can be compiled as C++ files
CPP_SOURCES := $(wildcard *.cpp)
CPP_OBJECTS := $(patsubst %.cpp,$(SUBDIR)/%.o,$(CPP_SOURCES))

# this adapts the make to find all .c files so they can be compiled as C files
C_SOURCES := $(wildcard *.c)
C_OBJECTS := $(patsubst %.c,$(SUBDIR)/%.o,$(C_SOURCES))

ifeq ($(WINDOWS),on)
# this adapts the make to find all .rc files so they can be compiled as resource files
RC_SOURCES := $(wildcard *.rc)
RC_OBJECTS := $(patsubst %.rc,$(SUBDIR)/%_rc.o,$(RC_SOURCES))
endif

# the set of objects is a set of one .o file for each source file, stored in the build-specific subdirectory
OBJECTS := $(RC_OBJECTS) $(C_OBJECTS) $(CPP_OBJECTS)

# the object library name is the library name with common conventions for library files applied
# don't generate a library if there are no object files to generate
ifeq ($(strip $(OBJECTS)),)
LIBRARY :=
else
LIBRARY := $(call archive_subpath,$(LIBNAME))
endif

# the set of include directories is the set of libraries
INCLUDES  := $(addprefix -I,$(LIBRARIES))

# the set of link libraries - use the library list and find the name and location of each library archive
# exclude those which do not have a Makefile because those are header-only libraries
ARCHIVE_LIBRARIES := $(foreach lib,$(LIBRARIES),$(call archive_library,$(lib)))
ARCHIVES := $(foreach lib,$(ARCHIVE_LIBRARIES),$(call archive_path,$(lib)))

################################################################################
# Now implement the make rules

.PHONY: all build run clean tidy FORCE

all:: build

build:: $(LIBRARY) $(ARCHIVE_LIBRARIES) $(IMAGE)

# Compilation Rules
# Also generate a dependency (.d) file. Dependency files are included in the make to detect out of date object files
# Note: gcc version 2.96 onwards put the .d files in the same place as the object files (correct)
#       earlier versions put the .d files in the current directory with the assumption that the object was there (wrong)
#       I no longer support those older versions

# the rule for compiling a C++ source file

$(SUBDIR)/%.o: %.cpp
	@echo "$(LIBNAME):$(SUBDIR): C++ compiling $<"
	@mkdir -p $(SUBDIR)
	$(CXX) -x c++ -c -MMD $(CPPFLAGS) $(CXXFLAGS) $(INCLUDES) $< -o $@

# the rule for compiling a C source file

$(SUBDIR)/%.o: %.c
	@echo "$(LIBNAME):$(SUBDIR): C compiling $<"
	@mkdir -p $(SUBDIR)
	$(CC) -x c -c -MMD $(CPPFLAGS) $(CFLAGS) $(INCLUDES) $< -o $@

ifeq ($(WINDOWS),on)
# the rule for compiling a resource file
# Note: add _rc suffix to object name because I tend to name the resource file the same as the main C++ source file
$(SUBDIR)/%_rc.o: %.rc
	@echo "$(LIBNAME):$(SUBDIR): RC compiling $<"
	@mkdir -p $(SUBDIR)
	$(RC) $(RCFLAGS) $< -o $@
endif

# Detect that a file is out of date with respect to its headers by including
# make rules generated during the last compilation of the file.
# Note: if a header file is deleted or moved then you can get an error since
# Make tries to find a rule to recreate that file. The solution is to delete
# the object library subdirectory (make clean) and do a clean build
-include $(SUBDIR)/*.d

# the rule for making an object library out of object files

$(LIBRARY): $(OBJECTS)
	@echo "$(LIBNAME):$(SUBDIR): Updating library $@"
	$(AR) crus $(LIBRARY) $(OBJECTS)

# The library dependencies are only built and the image is only linked if the IMAGE variable is defined
# only update other libraries if we are linking since just building an object library doesn't need the
# dependency libraries to be up to date

ifneq ($(IMAGE),)

# the rule for building the library dependencies unconditionally runs a recursive Make

$(ARCHIVE_LIBRARIES): FORCE
	$(MAKE) -C $@

# the rule for linking an image

$(IMAGE): $(LIBRARY) $(ARCHIVES)
	@echo "$(LIBNAME):$(SUBDIR): $(BUILD_TYPE) Linking $(IMAGE)"
	@echo "$(LIBNAME):$(SUBDIR):   flags: $(LDFLAGS)"
	@for l in $(LIBRARY) $(ARCHIVES); do echo "$(LIBNAME):$(SUBDIR):   using: $$l"; done
	@echo "$(LIBNAME):$(SUBDIR):   libs: $(LOADLIBES)"
	@mkdir -p $(dir $(IMAGE))
	$(CXX) $(LDFLAGS) $(RC_OBJECTS) $^ $(LOADLIBES) -o $(IMAGE)

endif

# the rule for running an image

ifneq ($(IMAGE),)

# if the image has no path, run it in the current directory, otherwise use the path
run: build
ifeq ($(findstring /,$(IMAGE)),)
	./$(IMAGE)
else
	$(IMAGE)
endif

endif

tidy::
	@if [ -d "$(SUBDIR)" ]; then echo "$(LIBNAME): Tidy: deleting $(SUBDIR)"; rm -rf "$(SUBDIR)"; fi
	@/usr/bin/find . -name '*.tmp' -exec echo "$(LIBNAME): Tidy: deleting " {} \; -exec rm {} \;
ifeq ($(GCOV),on)
	@/usr/bin/find . -name '*.gcov' -exec echo "$(LIBNAME): Tidy: deleting " {} \; -exec rm {} \;
endif

clean:: tidy
ifneq ($(IMAGE),)
	@if [ -f "$(IMAGE).exe" ]; then echo "$(LIBNAME): Clean: deleting $(IMAGE).exe"; rm -f "$(IMAGE).exe"; fi
	@if [ -f "$(IMAGE)" ]; then echo "$(LIBNAME): Clean: deleting $(IMAGE)"; rm -f "$(IMAGE)"; fi
endif
