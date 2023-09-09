# cmake bits to do a full static build, downloading and building all dependencies.

# Most of these are CACHE STRINGs so that you can override them using -DWHATEVER during cmake
# invocation to override.

set(LOCAL_MIRROR "" CACHE STRING "local mirror path/URL for lib downloads")

set(OPENSSL_VERSION 1.1.1i CACHE STRING "openssl version")
set(OPENSSL_MIRROR ${LOCAL_MIRROR} https://www.openssl.org/source CACHE STRING "openssl download mirror(s)")
set(OPENSSL_SOURCE openssl-${OPENSSL_VERSION}.tar.gz)
set(OPENSSL_HASH SHA256=e8be6a35fe41d10603c3cc635e93289ed00bf34b79671a3a4de64fcee00d5242
    CACHE STRING "openssl source hash")

set(BOOST_VERSION 1.75.0 CACHE STRING "boost version")
set(BOOST_MIRROR ${LOCAL_MIRROR} https://dl.bintray.com/boostorg/release/${BOOST_VERSION}/source
    CACHE STRING "boost download mirror(s)")
string(REPLACE "." "_" BOOST_VERSION_ ${BOOST_VERSION})
set(BOOST_SOURCE boost_${BOOST_VERSION_}.tar.bz2)
set(BOOST_HASH SHA256=953db31e016db7bb207f11432bef7df100516eeb746843fa0486a222e3fd49cb
    CACHE STRING "boost source hash")

set(SODIUM_VERSION 1.0.18 CACHE STRING "libsodium version")
set(SODIUM_MIRROR ${LOCAL_MIRROR}
  https://download.libsodium.org/libsodium/releases
  https://github.com/jedisct1/libsodium/releases/download/${SODIUM_VERSION}-RELEASE
  CACHE STRING "libsodium mirror(s)")
set(SODIUM_SOURCE libsodium-${SODIUM_VERSION}.tar.gz)
set(SODIUM_HASH SHA512=17e8638e46d8f6f7d024fe5559eccf2b8baf23e143fadd472a7d29d228b186d86686a5e6920385fe2020729119a5f12f989c3a782afbd05a8db4819bb18666ef
  CACHE STRING "libsodium source hash")

set(SQLITE3_VERSION 3340000 CACHE STRING "sqlite3 version")
set(SQLITE3_MIRROR ${LOCAL_MIRROR} https://www.sqlite.org/2020
    CACHE STRING "sqlite3 download mirror(s)")
set(SQLITE3_SOURCE sqlite-autoconf-${SQLITE3_VERSION}.tar.gz)
set(SQLITE3_HASH SHA512=75a1a2d86ab41354941b8574e780b1eae09c3c01f8da4b08f606b96962b80550f739ec7e9b1ceb07bba1cedced6d18a1408e4c10ff645eb1829d368ad308cf2f
    CACHE STRING "sqlite3 source hash")


include(ExternalProject)

set(DEPS_DESTDIR ${CMAKE_BINARY_DIR}/static-deps)
set(DEPS_SOURCEDIR ${CMAKE_BINARY_DIR}/static-deps-sources)

include_directories(BEFORE SYSTEM ${DEPS_DESTDIR}/include)

file(MAKE_DIRECTORY ${DEPS_DESTDIR}/include)

set(deps_cc "${CMAKE_C_COMPILER}")
set(deps_cxx "${CMAKE_CXX_COMPILER}")

if(CMAKE_C_COMPILER_LAUNCHER)
  set(deps_cc "${CMAKE_C_COMPILER_LAUNCHER} ${deps_cc}")
endif()
if(CMAKE_CXX_COMPILER_LAUNCHER)
  set(deps_cxx "${CMAKE_CXX_COMPILER_LAUNCHER} ${deps_cxx}")
endif()

function(expand_urls output source_file)
  set(expanded)
  foreach(mirror ${ARGN})
    list(APPEND expanded "${mirror}/${source_file}")
  endforeach()
  set(${output} "${expanded}" PARENT_SCOPE)
endfunction()

function(add_static_target target ext_target libname)
  add_library(${target} STATIC IMPORTED GLOBAL)
  add_dependencies(${target} ${ext_target})
  set_target_properties(${target} PROPERTIES
    IMPORTED_LOCATION ${DEPS_DESTDIR}/lib/${libname}
  )
endfunction()



if(USE_LTO)
  set(flto "-flto")
else()
  set(flto "")
endif()

set(cross_host "")
set(cross_extra "")
if(CMAKE_CROSSCOMPILING)
  if(APPLE)
    set(cross_host "--host=${APPLE_TARGET_TRIPLE}")
  else()
    set(cross_host "--host=${ARCH_TRIPLET}")
    if (ARCH_TRIPLET MATCHES mingw AND CMAKE_RC_COMPILER)
      set(cross_extra "WINDRES=${CMAKE_RC_COMPILER}")
    endif()
  endif()
endif()



set(deps_CFLAGS "-O2 ${flto}")
set(deps_CXXFLAGS "-O2 ${flto}")
set(deps_noarch_CFLAGS "${deps_CFLAGS}")
set(deps_noarch_CXXFLAGS "${deps_CXXFLAGS}")

if(APPLE)
  foreach(lang C CXX)
    string(APPEND deps_${lang}FLAGS " ${CMAKE_${lang}_SYSROOT_FLAG} ${CMAKE_OSX_SYSROOT}")
    if (CMAKE_OSX_DEPLOYMENT_TARGET)
        string(APPEND deps_${lang}FLAGS " ${CMAKE_${lang}_OSX_DEPLOYMENT_TARGET_FLAG}${CMAKE_OSX_DEPLOYMENT_TARGET}")
    endif()

    set(deps_noarch_${lang}FLAGS "${deps_${lang}FLAGS}")

    foreach(arch ${CMAKE_OSX_ARCHITECTURES})
      string(APPEND deps_${lang}FLAGS " -arch ${arch}")
    endforeach()
  endforeach()
endif()

# Builds a target; takes the target name (e.g. "readline") and builds it in an external project with
# target name suffixed with `_external`.  Its upper-case value is used to get the download details
# (from the variables set above).  The following options are supported and passed through to
# ExternalProject_Add if specified.  If omitted, these defaults are used:
set(build_def_DEPENDS "")
set(build_def_PATCH_COMMAND "")
set(build_def_CONFIGURE_COMMAND ./configure ${cross_host} --disable-shared --prefix=${DEPS_DESTDIR} --with-pic
    "CC=${deps_cc}" "CXX=${deps_cxx}" "CFLAGS=${deps_CFLAGS}" "CXXFLAGS=${deps_CXXFLAGS}" ${cross_extra})
set(build_def_BUILD_COMMAND make)
set(build_def_INSTALL_COMMAND make install)
set(build_def_BUILD_BYPRODUCTS ${DEPS_DESTDIR}/lib/lib___TARGET___.a ${DEPS_DESTDIR}/include/___TARGET___.h)
set(build_dep_TARGET_SUFFIX "")

function(build_external target)
  set(options TARGET_SUFFIX DEPENDS PATCH_COMMAND CONFIGURE_COMMAND BUILD_COMMAND INSTALL_COMMAND BUILD_BYPRODUCTS)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "" "${options}")
  foreach(o ${options})
    if(NOT DEFINED arg_${o})
      set(arg_${o} ${build_def_${o}})
    endif()
  endforeach()
  string(REPLACE ___TARGET___ ${target} arg_BUILD_BYPRODUCTS "${arg_BUILD_BYPRODUCTS}")

  string(TOUPPER "${target}" prefix)
  expand_urls(urls ${${prefix}_SOURCE} ${${prefix}_MIRROR})
  ExternalProject_Add("${target}${arg_TARGET_SUFFIX}_external"
    DEPENDS ${arg_DEPENDS}
    BUILD_IN_SOURCE ON
    PREFIX ${DEPS_SOURCEDIR}
    URL ${urls}
    URL_HASH ${${prefix}_HASH}
    DOWNLOAD_NO_PROGRESS ON
    PATCH_COMMAND ${arg_PATCH_COMMAND}
    CONFIGURE_COMMAND ${arg_CONFIGURE_COMMAND}
    BUILD_COMMAND ${arg_BUILD_COMMAND}
    INSTALL_COMMAND ${arg_INSTALL_COMMAND}
    BUILD_BYPRODUCTS ${arg_BUILD_BYPRODUCTS}
  )
endfunction()



set(openssl_configure ./config)
set(openssl_system_env "")
set(openssl_cc "${deps_cc}")
if(CMAKE_CROSSCOMPILING)
  if(ARCH_TRIPLET STREQUAL x86_64-w64-mingw32)
    set(openssl_system_env SYSTEM=MINGW64 RC=${CMAKE_RC_COMPILER})
  elseif(ARCH_TRIPLET STREQUAL i686-w64-mingw32)
    set(openssl_system_env SYSTEM=MINGW64 RC=${CMAKE_RC_COMPILER})
  endif()
endif()
build_external(openssl
  CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CC=${openssl_cc} ${openssl_system_env} ${openssl_configure}
    --prefix=${DEPS_DESTDIR} ${openssl_extra_opts} no-shared no-capieng no-dso no-dtls1 no-ec_nistp_64_gcc_128 no-gost
    no-heartbeats no-md2 no-rc5 no-rdrand no-rfc3779 no-sctp no-ssl-trace no-ssl2 no-ssl3
    no-static-engine no-tests no-weak-ssl-ciphers no-zlib-dynamic "CFLAGS=${deps_CFLAGS}"
  INSTALL_COMMAND make install_sw
  BUILD_BYPRODUCTS
    ${DEPS_DESTDIR}/lib/libssl.a ${DEPS_DESTDIR}/lib/libcrypto.a
    ${DEPS_DESTDIR}/include/openssl/ssl.h ${DEPS_DESTDIR}/include/openssl/crypto.h
)
add_static_target(OpenSSL::SSL openssl_external libssl.a)
add_static_target(OpenSSL::Crypto openssl_external libcrypto.a)
set(OPENSSL_INCLUDE_DIR ${DEPS_DESTDIR}/include)
set(OPENSSL_VERSION 1.1.1)



set(boost_threadapi "pthread")
set(boost_bootstrap_cxx "CXX=${deps_cxx}")
set(boost_toolset "")
set(boost_extra "")
if(USE_LTO)
  list(APPEND boost_extra "lto=on")
endif()
if(CMAKE_CROSSCOMPILING)
  set(boost_bootstrap_cxx "") # need to use our native compiler to bootstrap
  if(ARCH_TRIPLET MATCHES mingw)
    set(boost_threadapi win32)
    list(APPEND boost_extra "target-os=windows")
    if(ARCH_TRIPLET MATCHES x86_64)
      list(APPEND boost_extra "address-model=64")
    else()
      list(APPEND boost_extra "address-model=32")
    endif()
  endif()
endif()
if(CMAKE_CXX_COMPILER_ID STREQUAL GNU)
  set(boost_toolset gcc)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "^(Apple)?Clang$")
  set(boost_toolset clang)
else()
  message(FATAL_ERROR "don't know how to build boost with ${CMAKE_CXX_COMPILER_ID}")
endif()

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/user-config.bjam "using ${boost_toolset} : : ${deps_cxx} ;")

set(boost_buildflags "cxxflags=-fPIC")
if(APPLE AND CMAKE_OSX_DEPLOYMENT_TARGET)
  string(APPEND boost_buildflags " -mmacosx-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}" "cflags=-mmacosx-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()

set(boost_libs program_options system)
if(BUILD_TESTS)
    list(APPEND boost_libs unit_test_framework)
endif()
string(REPLACE ";" "," boost_with_libraries "${boost_libs}")
set(boost_static_libraries)
foreach(lib ${boost_libs})
    list(APPEND boost_static_libraries "${DEPS_DESTDIR}/lib/libboost_${lib}.a")
endforeach()

build_external(boost
  #  PATCH_COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}/user-config.bjam tools/build/src/user-config.jam
  CONFIGURE_COMMAND
    ${CMAKE_COMMAND} -E env ${boost_bootstrap_cxx}
    ./bootstrap.sh --without-icu --prefix=${DEPS_DESTDIR} --with-toolset=${boost_toolset}
      --with-libraries=${boost_with_libraries}
  BUILD_COMMAND true
  INSTALL_COMMAND
    ./b2 -d0 variant=release link=static runtime-link=static optimization=speed ${boost_extra}
      threading=multi threadapi=${boost_threadapi} ${boost_buildflags} cxxstd=14 visibility=global
      --disable-icu --user-config=${CMAKE_CURRENT_BINARY_DIR}/user-config.bjam
      install
  BUILD_BYPRODUCTS
    ${boost_static_libraries}
    ${DEPS_DESTDIR}/include/boost/version.hpp
)
add_library(boost_core INTERFACE)
add_dependencies(boost_core INTERFACE boost_external)
target_include_directories(boost_core SYSTEM INTERFACE ${DEPS_DESTDIR}/include)
add_library(Boost::boost ALIAS boost_core)
foreach(lib ${boost_libs})
  add_static_target(Boost::${lib} boost_external libboost_${lib}.a)
  target_link_libraries(Boost::${lib} INTERFACE boost_core)
endforeach()
set(Boost_FOUND ON)
set(Boost_VERSION ${BOOST_VERSION})



build_external(sqlite3
  BUILD_COMMAND true
  INSTALL_COMMAND make install-includeHEADERS install-libLTLIBRARIES)
add_static_target(sqlite3 sqlite3_external libsqlite3.a)



build_external(sodium)
add_static_target(sodium sodium_external libsodium.a)


if(ZMQ_VERSION VERSION_LESS 4.3.4 AND CMAKE_CROSSCOMPILING AND ARCH_TRIPLET MATCHES mingw)
  set(zmq_patch PATCH_COMMAND patch -p1 -i ${PROJECT_SOURCE_DIR}/utils/build_scripts/libzmq-mingw-closesocket.patch)
endif()

set(zmq_cross_host "${cross_host}")


