#pragma once

#include "sispop_logger.h"

#include <iostream>

#define VERSION_MAJOR 2
#define VERSION_MINOR 0
#define VERSION_PATCH 9

#define SISPOP_STRINGIFY2(val) #val
#define SISPOP_STRINGIFY(val) SISPOP_STRINGIFY2(val)

#define VERSION_MAJOR_STR SISPOP_STRINGIFY(VERSION_MAJOR)
#define VERSION_MINOR_STR SISPOP_STRINGIFY(VERSION_MINOR)
#define VERSION_PATCH_STR SISPOP_STRINGIFY(VERSION_PATCH)

#ifndef STORAGE_SERVER_VERSION_STRING
#define STORAGE_SERVER_VERSION_STRING                                          \
    VERSION_MAJOR_STR "." VERSION_MINOR_STR "." VERSION_PATCH_STR
#endif

#ifndef STORAGE_SERVER_GIT_HASH_STRING
#define STORAGE_SERVER_GIT_HASH_STRING "?"
#endif

#ifndef STORAGE_SERVER_BUILD_TIME
#define STORAGE_SERVER_BUILD_TIME "?"
#endif

static void print_version() {
    SISPOP_LOG(info,
             "Sispop Storage Server v{}\n git commit hash: {}\n build time: {}",
             STORAGE_SERVER_VERSION_STRING, STORAGE_SERVER_GIT_HASH_STRING,
             STORAGE_SERVER_BUILD_TIME);
}
