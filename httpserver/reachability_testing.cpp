
#include "reachability_testing.h"
#include "sispop_logger.h"

using std::chrono::steady_clock;
using namespace std::chrono_literals;

namespace sispop {

namespace detail {

reach_record_t::reach_record_t() {
    this->first_failure = steady_clock::now();
    this->last_tested = this->first_failure;
}

} // namespace detail

/// How long to wait until reporting unreachable nodes to Sispopd
constexpr std::chrono::minutes UNREACH_GRACE_PERIOD = 120min;

bool reachability_records_t::record_unreachable(const sn_pub_key_t& sn) {

    const auto it = offline_nodes_.find(sn);

    if (it == offline_nodes_.end()) {
        /// TODO: change this to debug
        SISPOP_LOG(debug, "Adding a new node to UNREACHABLE: {}", sn);
        offline_nodes_.insert({sn, {}});
    } else {
        SISPOP_LOG(debug, "Node is ALREAY known to be UNREACHABLE: {}", sn);

        it->second.last_tested = steady_clock::now();

        const auto elapsed = it->second.last_tested - it->second.first_failure;
        const auto elapsed_sec =
            std::chrono::duration_cast<std::chrono::seconds>(elapsed).count();
        SISPOP_LOG(debug, "First time failed {} seconds ago", elapsed_sec);

        /// TODO: Might still want to report as unreachable since this status
        /// gets reset to `true` on Sispopd restart
        if (it->second.reported) {
            SISPOP_LOG(debug, "Already reported node: {}", sn);
        } else if (elapsed > UNREACH_GRACE_PERIOD) {
            SISPOP_LOG(debug, "Will REPORT this node to Sispopd!");
            return true;
        }

    }

    return false;
}

bool reachability_records_t::expire(const sn_pub_key_t& sn) {

    bool erased = offline_nodes_.erase(sn);
    if (erased)
        SISPOP_LOG(debug, "Removed entry for {}", sn);

    return erased;
}

void reachability_records_t::set_reported(const sn_pub_key_t& sn) {

    const auto it = offline_nodes_.find(sn);
    if (it != offline_nodes_.end()) {
        it->second.reported = true;
    }
}

boost::optional<sn_pub_key_t> reachability_records_t::next_to_test() {

    const auto it = std::min_element(
        offline_nodes_.begin(), offline_nodes_.end(),
        [&](const auto& lhs, const auto& rhs) {
            return lhs.second.last_tested < rhs.second.last_tested;
        });

    if (it == offline_nodes_.end()) {
        return boost::none;
    } else {

        SISPOP_LOG(debug, "Selecting to be re-tested: {}", it->first);

        return it->first;
    }
}

} // namespace sispop
