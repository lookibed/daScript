options gen2

require dastest/review_gate

// The mechanical half of modules/dasFlex/REVIEW.md (contract:
// REVIEW_COMMON.md at the repo root). Run from the repo root:
// bin/daslang modules/dasFlex/REVIEW.das - exit 0 clean, 1 with
// findings.

[export]
def main : int {
    gate_reset()
    gate_descriptor_census("modules/dasFlex/.das_module", ["modules/dasFlex/flex"], { "flex" })
    gate_lane_census("modules/dasFlex/CMakeLists.txt", "modules/dasFlex/tests")
    return gate_verdict("dasFlex")
}
