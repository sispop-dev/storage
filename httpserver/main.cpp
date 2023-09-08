#include "channel_encryption.hpp"
#include "command_line.h"
#include "http_connection.h"
#include "sispop_logger.h"
#include "sispopd_key.h"
#include "rate_limiter.h"
#include "security.h"
#include "service_node.h"
#include "swarm.h"
#include "version.h"
#include "utils.hpp"

#include <boost/filesystem.hpp>
#include <sodium.h>

#include <cstdlib>
#include <iostream>
#include <vector>

namespace fs = boost::filesystem;

static boost::optional<fs::path> get_home_dir() {

    /// TODO: support default dir for Windows
#ifdef WIN32
    return boost::none;
#endif

    char* pszHome = getenv("HOME");
    if (pszHome == NULL || strlen(pszHome) == 0)
        return boost::none;

    return fs::path(pszHome);
}

constexpr int EXIT_INVALID_PORT = 2;

int main(int argc, char* argv[]) {

    sispop::command_line_parser parser;

    try {
        parser.parse_args(argc, argv);
    } catch (const std::exception& e) {
        std::cerr << e.what() << std::endl;
        parser.print_usage();
        return EXIT_FAILURE;
    }

    auto options = parser.get_options();

    if (options.print_help) {
        parser.print_usage();
        return EXIT_SUCCESS;
    }

    if (options.data_dir.empty()) {
        if (auto home_dir = get_home_dir()) {
            if (options.testnet) {
                options.data_dir = (home_dir.get() / ".sispop" / "testnet" / "storage").string();
            } else {
                options.data_dir = (home_dir.get() / ".sispop" / "storage").string();
            }
        }
    }

    if (!fs::exists(options.data_dir)) {
        fs::create_directories(options.data_dir);
    }

    sispop::LogLevel log_level;
    if (!sispop::parse_log_level(options.log_level, log_level)) {
        std::cerr << "Incorrect log level: " << options.log_level << std::endl;
        sispop::print_log_levels();
        return EXIT_FAILURE;
    }

    sispop::init_logging(options.data_dir, log_level);

    if (options.testnet) {
        sispop::set_testnet();
        SISPOP_LOG(warn, "Starting in testnet mode, make sure this is intentional!");
    }

    // Always print version for the logs
    print_version();
    if (options.print_version) {
        return EXIT_SUCCESS;
    }

    if (options.ip == "127.0.0.1") {
        SISPOP_LOG(critical,
                 "Tried to bind sispop-storage to localhost, please bind "
                 "to outward facing address");
        return EXIT_FAILURE;
    }

    if (options.port == options.sispopd_rpc_port) {
        SISPOP_LOG(error, "Storage server port must be different from that of "
                        "Sispopd! Terminating.");
        exit(EXIT_INVALID_PORT);
    }

    SISPOP_LOG(info, "Setting log level to {}", options.log_level);
    SISPOP_LOG(info, "Setting database location to {}", options.data_dir);
    SISPOP_LOG(info, "Setting Sispopd RPC to {}:{}", options.sispopd_rpc_ip, options.sispopd_rpc_port);
    SISPOP_LOG(info, "Listening at address {} port {}", options.ip, options.port);

    boost::asio::io_context ioc{1};
    boost::asio::io_context worker_ioc{1};

    if (sodium_init() != 0) {
        SISPOP_LOG(error, "Could not initialize libsodium");
        return EXIT_FAILURE;
    }

    {
        const auto fd_limit = util::get_fd_limit();
        if (fd_limit != -1) {
            SISPOP_LOG(debug, "Open file descriptor limit: {}", fd_limit);
        } else {
            SISPOP_LOG(debug, "Open descriptor limit: N/A");
        }
    }

    try {

        auto sispopd_client = sispop::SispopdClient(ioc, options.sispopd_rpc_ip, options.sispopd_rpc_port);

        // Normally we request the key from daemon, but in integrations/swarm
        // testing we are not able to do that, so we extract the key as a
        // command line option:
        sispop::private_key_t private_key;
        sispop::private_key_ed25519_t private_key_ed25519; // Unused at the moment
        sispop::private_key_t private_key_x25519;
#ifndef INTEGRATION_TEST
        std::tie(private_key, private_key_ed25519, private_key_x25519) =
            sispopd_client.wait_for_privkey();
#else
        private_key = sispop::sispopdKeyFromHex(options.sispopd_key);
        SISPOP_LOG(info, "SISPOPD LEGACY KEY: {}", options.sispopd_key);

        private_key_x25519 = sispop::sispopdKeyFromHex(options.sispopd_x25519_key);
        SISPOP_LOG(info, "x25519 SECRET KEY: {}", options.sispopd_x25519_key);

        private_key_ed25519 = sispop::private_key_ed25519_t::from_hex(options.sispopd_ed25519_key);

        SISPOP_LOG(info, "ed25519 SECRET KEY: {}", options.sispopd_ed25519_key);
#endif

        const auto public_key = sispop::derive_pubkey_legacy(private_key);
        SISPOP_LOG(info, "Retrieved keys from Sispopd; our SN pubkey is: {}",
                 util::as_hex(public_key));

        // TODO: avoid conversion to vector
        const std::vector<uint8_t> priv(private_key_x25519.begin(),
                                        private_key_x25519.end());
        ChannelEncryption<std::string> channel_encryption(priv);

        sispop::sispopd_key_pair_t sispopd_key_pair{private_key, public_key};

        const auto public_key_x25519 =
            sispop::derive_pubkey_x25519(private_key_x25519);

        SISPOP_LOG(info, "SN x25519 pubkey is: {}",
                 util::as_hex(public_key_x25519));

        const auto public_key_ed25519 =
            sispop::derive_pubkey_ed25519(private_key_ed25519);

        SISPOP_LOG(info, "SN ed25519 pubkey is: {}",
                 util::as_hex(public_key_ed25519));

        sispop::sispopd_key_pair_t sispopd_key_pair_x25519{private_key_x25519,
                                                     public_key_x25519};

        sispop::ServiceNode service_node(ioc, worker_ioc, options.port,
                                       sispopd_key_pair, sispopd_key_pair_x25519,
                                       options.data_dir, sispopd_client,
                                       options.force_start);
        RateLimiter rate_limiter;

        sispop::Security security(sispopd_key_pair, options.data_dir);

        /// Should run http server
        sispop::http_server::run(ioc, options.ip, options.port, options.data_dir,
                               service_node, channel_encryption, rate_limiter,
                               security);
    } catch (const std::exception& e) {
        // It seems possible for logging to throw its own exception,
        // in which case it will be propagated to libc...
        std::cerr << "Exception caught in main: " << e.what() << std::endl;
        return EXIT_FAILURE;
    } catch (...) {
        std::cerr << "Unknown exception caught in main." << std::endl;
        return EXIT_FAILURE;
    }
}
