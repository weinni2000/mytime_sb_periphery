#!/usr/bin/env bash
# Warm sitemap URLs using the official sitewarm CLI, without overlapping runs.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

usage() {
    cat <<'EOF'
Usage: warm.sh [--dry-run] [SITEMAP_URL] [-- EXTRA_SITEWARM_FLAGS...]

Configure sitewarm.env or pass an absolute sitemap URL:
  ./warm.sh https://example.com/sitemap.xml
  ./warm.sh --dry-run https://example.com/sitemap.xml
  ./warm.sh https://example.com/sitemap.xml -- --top 20 --max-wait 20s

Install the CLI first with ./install.sh. Reports and logs go to reports/.
The scan follows sitemap indexes and respects robots.txt. Both desktop and
mobile profiles are requested. It fetches pages, not every page's images/JS.
EOF
}

dry_run=false
sitemap_override=
extra_args=()
while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --dry-run) dry_run=true; shift ;;
        --) shift; extra_args=("$@"); break ;;
        http://*|https://*)
            if [[ -n $sitemap_override ]]; then
                echo "Pass only one sitemap URL." >&2
                exit 2
            fi
            sitemap_override=$1
            shift
            ;;
        *) echo "Unknown argument: $1 (see --help)." >&2; exit 2 ;;
    esac
done

config_file=${SITEWARM_CONFIG:-$script_dir/sitewarm.env}
if [[ -f $config_file ]]; then
    # This is a trusted local shell configuration, never downloaded content.
    source "$config_file"
elif [[ -n ${SITEWARM_CONFIG:-} ]]; then
    echo "Configuration file not found: $config_file" >&2
    exit 2
fi
sitemap_url=${sitemap_override:-${SITEMAP_URL:-}}
if [[ ! $sitemap_url =~ ^https?://[^/]+/ ]]; then
    echo "Set SITEMAP_URL in sitewarm.env or pass a full sitemap URL (see --help)." >&2
    exit 2
fi

sitewarm_bin=${SITEWARM_BIN:-$script_dir/.bin/sitewarm}
report_dir=${SITEWARM_REPORT_DIR:-$script_dir/reports}
if [[ $report_dir != /* ]]; then
    report_dir="$script_dir/$report_dir"
fi
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
report_file="$report_dir/$run_id.json"
log_file="$report_dir/$run_id.log"
args=(
    scan --from-sitemap "$sitemap_url"
    --top "${SITEWARM_TOP:-1000000}"
    --rps "${SITEWARM_RPS:-2}"
    --concurrency "${SITEWARM_CONCURRENCY:-2}"
    --max-wait "${SITEWARM_MAX_WAIT:-0}"
    --retry-interval "${SITEWARM_RETRY_INTERVAL:-10s}"
    --run-timeout "${SITEWARM_RUN_TIMEOUT:-1h}"
    --accept-language "${SITEWARM_ACCEPT_LANGUAGE:-de-AT,de;q=0.9,en;q=0.8}"
    --fail-on "${SITEWARM_FAIL_ON:-miss,client-error,error,incomplete,redirect-error,challenged}"
    --format "${SITEWARM_FORMAT:-table}"
    --report "$report_file"
    "${extra_args[@]}"
)
if "$dry_run"; then
    printf '%q ' "$sitewarm_bin" "${args[@]}"
    printf '\n'
    exit 0
fi
if [[ ! -x $sitewarm_bin ]]; then
    echo "sitewarm executable not found: $sitewarm_bin. Run $script_dir/install.sh first." >&2
    exit 2
fi
if ! command -v flock >/dev/null 2>&1; then
    echo "flock is required (util-linux on Linux)." >&2
    exit 2
fi
exec 9>"$script_dir/.run.lock"
if ! flock -n 9; then
    echo "A sitewarm scan is already running; skipping."
    exit 0
fi

mkdir -p "$report_dir"
echo "JSON report: $report_file"
echo "Log: $log_file"
set +e
"$sitewarm_bin" "${args[@]}" 2>&1 | tee "$log_file"
pipeline_status=("${PIPESTATUS[@]}")
set -e
if ((pipeline_status[1] != 0)); then
    echo "Failed to write the scan log." >&2
    exit 1
fi
exit "${pipeline_status[0]}"
