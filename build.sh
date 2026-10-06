#!/bin/zsh
# Local CrossOver/Quartus build. Never launches Quartus as part of make test.
# Usage: ./build.sh map|compile
set -euo pipefail
cd "$(dirname "$0")"

cx_bin=${CROSSOVER_BIN:-/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin}
quartus_bottle=${QUARTUS_BOTTLE:-Quartus}
quartus_bin=${QUARTUS_BIN:-C:/intelFPGA_lite/17.0/quartus/bin64}
build_mode=${1:-compile}
case "$build_mode" in
    map|compile) ;;
    *) print -u2 'Usage: ./build.sh map|compile'; exit 1 ;;
esac

mkdir -p build
# Synthesis-only runs do not invoke the framework pre-flow date generator.
print -r -- "\`define BUILD_DATE \"$(date +%y%m%d)\"" > build_id.v

if [[ "$build_mode" == map ]]; then
    "$cx_bin/wine" --bottle "$quartus_bottle" --workdir "$PWD" --cx-app \
        "$quartus_bin/quartus_map.exe" --read_settings_files=on --write_settings_files=off \
        DifferenceEngine -c DifferenceEngine 2>&1 | tee build/quartus-map.log
else
    "$cx_bin/wine" --bottle "$quartus_bottle" --workdir "$PWD" --cx-app \
        "$quartus_bin/quartus_sh.exe" --flow compile DifferenceEngine 2>&1 | tee build/quartus-compile.log
    if rg -q 'Timing requirements not met' build/quartus-compile.log; then
        print -u2 'Quartus produced output, but timing requirements were not met.'
        exit 2
    fi
    "$cx_bin/wine" --bottle "$quartus_bottle" --workdir "$PWD" --cx-app \
        "$quartus_bin/quartus_sta.exe" -t tools/report_timing.tcl 2>&1 | tee build/timing-report.log
    test -s output_files/DifferenceEngine.rbf
fi
