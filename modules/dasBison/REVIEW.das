options gen2

require dastest/review_gate

// The mechanical half of modules/dasBison/REVIEW.md (contract:
// REVIEW_COMMON.md at the repo root). Run from the repo root:
// bin/daslang modules/dasBison/REVIEW.das - exit 0 clean, 1 with
// findings.

[export]
def main : int {
    gate_reset()
    gate_descriptor_census("modules/dasBison/.das_module", ["modules/dasBison/bison"], { "bison" })
    gate_lane_census("modules/dasBison/CMakeLists.txt", "modules/dasBison/tests")
    return gate_verdict("dasBison")
}
