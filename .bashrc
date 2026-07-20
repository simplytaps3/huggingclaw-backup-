export PATH="/home/node/.local/bin:$PATH"
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-/home/node/.local}"
export npm_config_prefix="$NPM_CONFIG_PREFIX"
export PYTHONUSERBASE="${PYTHONUSERBASE:-/home/node/.local}"
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
if [ -z "${PS1:-}" ] || [ "$PS1" = "$ " ]; then
  export PS1="\u@\h:\w\$ "
fi
STARTUP_FILE="/home/node/.openclaw/workspace/startup.sh"
_hc_append() {
  if [ "${HUGGINGCLAW_CAPTURE_DISABLE:-0}" = "1" ]; then
    return 0
  fi
  local line="$*"
  mkdir -p "$(dirname "$STARTUP_FILE")"
  touch "$STARTUP_FILE"
  chmod +x "$STARTUP_FILE" 2>/dev/null || true
  grep -qxF "$line" "$STARTUP_FILE" 2>/dev/null || echo "$line" >> "$STARTUP_FILE"
}
_hc_quote_args() {
  local quoted=()
  local arg
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    quoted+=("$arg")
  done
  printf '%s' "${quoted[*]}"
}
_hc_append_cmd() {
  local cmd="$1"
  shift
  local args
  args=$(_hc_quote_args "$@")
  if [ -n "$args" ]; then
    _hc_append "$cmd $args"
  else
    _hc_append "$cmd"
  fi
}
_hc_args_without_flags() {
  local out=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      ''|-) ;;
      --*) ;;
      -*) ;;
      *) out+=("$arg") ;;
    esac
  done
  printf '%s\n' "${out[@]}"
}
_hc_has_install_targets() {
  local item
  while IFS= read -r item; do
    [ -n "$item" ] && return 0
  done <<EOF
$(_hc_args_without_flags "$@")
EOF
  return 1
}
_hc_allow_openclaw_plugins() {
  local config="/home/node/.openclaw/openclaw.json"
  [ -f "$config" ] || return 0

  local plugins=()
  local plugin
  for plugin in "$@"; do
    [ -n "$plugin" ] || continue
    [[ "$plugin" == -* ]] && continue
    plugins+=("$plugin")
    if [[ "$plugin" == @openclaw/* ]]; then
      plugins+=("${plugin#@openclaw/}")
    fi
  done
  [ "${#plugins[@]}" -gt 0 ] || return 0

  local plugins_json
  plugins_json=$(printf '%s\n' "${plugins[@]}" | jq -R 'select(length > 0)' | jq -s 'unique') || return 0
  jq --argjson plugins "$plugins_json" \
    '.plugins.allow = (((.plugins.allow // []) + $plugins) | unique)' \
    "$config" > "$config.tmp" && mv "$config.tmp" "$config"
}
_hc_has_arg() {
  local needle="$1"
  shift
  local arg
  for arg in "$@"; do
    [ "$arg" = "$needle" ] && return 0
  done
  return 1
}
_hc_can_sudo_apt() {
  command -v sudo >/dev/null 2>&1 && sudo -n apt-get --version >/dev/null 2>&1
}
_hc_apt_install() {
  if [ "$(id -u)" -eq 0 ]; then
    command apt-get update && command apt-get install -y "$@"
  elif _hc_can_sudo_apt; then
    sudo apt-get update && sudo apt-get install -y "$@"
  else
    echo "Error: apt install needs root. Rebuild with the latest HuggingClaw image or add packages to Dockerfile." >&2
    return 1
  fi
}
apt-get() {
  case "${1:-}" in
    install)
      shift
      _hc_apt_install "$@"
      local rc=$?
      if [ $rc -eq 0 ]; then
        _hc_has_install_targets "$@" && _hc_append_cmd "sudo apt-get update && sudo apt-get install -y" "$@"
      fi
      return $rc
      ;;
    update)
      if [ "$(id -u)" -eq 0 ]; then
        command apt-get "$@"
      elif _hc_can_sudo_apt; then
        sudo apt-get "$@"
      else
        command apt-get "$@"
      fi
      return $?
      ;;
    *)
      command apt-get "$@"
      return $?
      ;;
  esac
}
apt() {
  case "${1:-}" in
    install)
      shift
      _hc_apt_install "$@"
      local rc=$?
      if [ $rc -eq 0 ]; then
        _hc_has_install_targets "$@" && _hc_append_cmd "sudo apt-get update && sudo apt-get install -y" "$@"
      fi
      return $rc
      ;;
    update)
      if [ "$(id -u)" -eq 0 ]; then
        command apt "$@"
      elif _hc_can_sudo_apt; then
        sudo apt "$@"
      else
        command apt "$@"
      fi
      return $?
      ;;
    *)
      command apt "$@"
      return $?
      ;;
  esac
}
pip() {
  if [ "${1:-}" = "install" ] && [ -z "${VIRTUAL_ENV:-}" ] && ! _hc_has_arg --user "$@" && ! _hc_has_arg --prefix "$@"; then
    command pip install --user --break-system-packages "${@:2}"
  else
    command pip "$@"
  fi
  local rc=$?
  # Skip capture when -r/--requirement is used: the requirements file won't exist on next boot
  if [ $rc -eq 0 ] && [ "${1:-}" = "install" ] \
      && ! _hc_has_arg -r "${@:2}" && ! _hc_has_arg --requirement "${@:2}" \
      && _hc_has_install_targets "${@:2}"; then
    _hc_append_cmd "python3 -m pip install --user" "${@:2}"
  fi
  return $rc
}
pip3() {
  if [ "${1:-}" = "install" ] && [ -z "${VIRTUAL_ENV:-}" ] && ! _hc_has_arg --user "$@" && ! _hc_has_arg --prefix "$@"; then
    command pip3 install --user --break-system-packages "${@:2}"
  else
    command pip3 "$@"
  fi
  local rc=$?
  if [ $rc -eq 0 ] && [ "${1:-}" = "install" ] \
      && ! _hc_has_arg -r "${@:2}" && ! _hc_has_arg --requirement "${@:2}" \
      && _hc_has_install_targets "${@:2}"; then
    _hc_append_cmd "python3 -m pip install --user" "${@:2}"
  fi
  return $rc
}
python() {
  if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pip" ] && [ "${3:-}" = "install" ] && [ -z "${VIRTUAL_ENV:-}" ] && ! _hc_has_arg --user "${@:3}" && ! _hc_has_arg --prefix "${@:3}"; then
    command python -m pip install --user --break-system-packages "${@:4}"
  else
    command python "$@"
  fi
  local rc=$?
  if [ $rc -eq 0 ] && [ "${1:-}" = "-m" ] && [ "${2:-}" = "pip" ] && [ "${3:-}" = "install" ] \
      && ! _hc_has_arg -r "${@:4}" && ! _hc_has_arg --requirement "${@:4}" \
      && _hc_has_install_targets "${@:4}"; then
    _hc_append_cmd "python3 -m pip install --user" "${@:4}"
  fi
  return $rc
}
python3() {
  if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pip" ] && [ "${3:-}" = "install" ] && [ -z "${VIRTUAL_ENV:-}" ] && ! _hc_has_arg --user "${@:3}" && ! _hc_has_arg --prefix "${@:3}"; then
    command python3 -m pip install --user --break-system-packages "${@:4}"
  else
    command python3 "$@"
  fi
  local rc=$?
  if [ $rc -eq 0 ] && [ "${1:-}" = "-m" ] && [ "${2:-}" = "pip" ] && [ "${3:-}" = "install" ] \
      && ! _hc_has_arg -r "${@:4}" && ! _hc_has_arg --requirement "${@:4}" \
      && _hc_has_install_targets "${@:4}"; then
    _hc_append_cmd "python3 -m pip install --user" "${@:4}"
  fi
  return $rc
}
npm() {
  command npm "$@"
  local rc=$?
  if [ $rc -eq 0 ] && { [ "${1:-}" = "install" ] || [ "${1:-}" = "i" ]; } && { [ "${2:-}" = "-g" ] || [ "${2:-}" = "--global" ]; } && _hc_has_install_targets "${@:3}"; then
    _hc_append_cmd "npm install -g" "${@:3}"
  fi
  return $rc
}
openclaw() {
  command openclaw "$@"
  local rc=$?
  if [ $rc -eq 0 ] && [ "${1:-}" = "plugins" ] && [ "${2:-}" = "install" ] && _hc_has_install_targets "${@:3}"; then
    _hc_allow_openclaw_plugins "${@:3}"
    _hc_append_cmd "openclaw plugins install" "${@:3}"
  fi
  return $rc
}
# uv pip install — increasingly popular fast pip replacement
uv() {
  command uv "$@"
  local rc=$?
  # Only capture: uv pip install ... (not uv pip sync, uv add, etc.)
  # Skip if -r/--requirements flag present (file won't exist on next boot)
  if [ $rc -eq 0 ] && [ "${1:-}" = "pip" ] && [ "${2:-}" = "install" ] \
      && ! _hc_has_arg -r "${@:3}" && ! _hc_has_arg --requirements "${@:3}" \
      && _hc_has_install_targets "${@:3}"; then
    _hc_append_cmd "uv pip install" "${@:3}"
  fi
  return $rc
}
# pipx — isolated tool installs
pipx() {
  command pipx "$@"
  local rc=$?
  if [ $rc -eq 0 ] && [ "${1:-}" = "install" ] && _hc_has_install_targets "${@:2}"; then
    _hc_append_cmd "pipx install" "${@:2}"
  fi
  return $rc
}
