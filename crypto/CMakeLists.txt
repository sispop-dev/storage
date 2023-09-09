cmake_minimum_required(VERSION 3.5)

add_library(crypto STATIC
    src/sispopd_key.cpp
    src/channel_encryption.cpp
    src/signature.cpp
    ${CMAKE_CURRENT_LIST_DIR}/../vendors/sispop/crypto-ops/crypto-ops.c
    ${CMAKE_CURRENT_LIST_DIR}/../vendors/sispop/crypto-ops/crypto-ops-data.c
    ${CMAKE_CURRENT_LIST_DIR}/../vendors/sispop/crypto-ops/keccak.c
    ${CMAKE_CURRENT_LIST_DIR}/../vendors/sispop/crypto-ops/hash-ops.c
)


target_include_directories(crypto
    PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}/include
    PRIVATE
    OpenSSL::SSL
    ${CMAKE_CURRENT_LIST_DIR}/../vendors
)

target_link_libraries(crypto PUBLIC utils)

#add_executable(crypto_test src/test_main.cpp)
#target_link_libraries(crypto_test  PRIVATE crypto)

find_package(Threads)

target_link_libraries(crypto PRIVATE
    sodium
    Boost::boost
    filesystem
    Threads::Threads
    ${CMAKE_DL_LIBS})
