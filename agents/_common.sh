# Shared by agents/*.sh (sourced, not run). preflight.sh sets APF_NET (an --internal Docker network) and
# APF_PROXY (the egress proxy on it, which allows only this agent's ALLOW_HOST). The agent container
# sits only on that network: no DNS, no route out, except HTTPS to its own provider through the proxy.

: "${APF_NET:?run agents through preflight.sh, which sets up the network limit}"
: "${APF_PROXY:?run agents through preflight.sh, which sets up the network limit}"

# agent_run <image> [docker run options...] -- <command...>   (stdin is passed through)
agent_run() {
  local image=$1; shift
  local opts=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do opts+=("$1"); shift; done
  shift
  docker run --rm -i --cap-drop ALL --security-opt no-new-privileges --network "$APF_NET" \
    -e HTTPS_PROXY="$APF_PROXY" -e https_proxy="$APF_PROXY" -e HTTP_PROXY="$APF_PROXY" -e http_proxy="$APF_PROXY" \
    -e NO_PROXY= -e no_proxy= "${opts[@]}" "$image" "$@"
}
