#pragma once

#include <boost/program_options.hpp>
#include <string>

namespace sispop {

struct command_line_options {
    uint16_t port;
    std::string sispopd_rpc_ip = "127.0.0.1";
    uint16_t sispopd_rpc_port = 30000; // Or 38157 if `testnet`
    bool force_start = false;
    bool print_version = false;
    bool print_help = false;
    bool testnet = false;
    std::string ip;
    std::string log_level = "info";
    std::string data_dir;
    std::string sispopd_key; // test only (but needed for backwards compatibility)
    std::string sispopd_x25519_key; // test only
    std::string sispopd_ed25519_key; // test only
};

class command_line_parser {
  public:
    void parse_args(int argc, char* argv[]);
    bool early_exit() const;

    const command_line_options& get_options() const;
    void print_usage() const;

  private:
    boost::program_options::options_description desc_;
    command_line_options options_;
    std::string binary_name_;
};

} // namespace sispop
