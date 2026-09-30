#!/usr/bin/env bash

set -euo pipefail

# Global variables for the bootstrap process.
OS=""
DISTRO=""
VERSION=""

# Detect the operating system and Linux distribution.
detect_os() {

	case "$(uname -s 2>/dev/null || printf 'Unknown')" in
		Linux)
			OS="Linux"
			if [[ -r /etc/os-release ]]; then
				# shellcheck disable=SC1091
				source /etc/os-release
				DISTRO="${ID:-${NAME:-Unknown}}"
				VERSION="${VERSION_ID:-${VERSION:-Unknown}}"
			else
				DISTRO="Unknown"
				VERSION="Unknown"
			fi
			;;
		Darwin)
			OS="Darwin"
			DISTRO="$(sw_vers -productName 2>/dev/null || printf 'macOS')"
			VERSION="$(sw_vers -productVersion 2>/dev/null || printf 'Unknown')"
			;;
		*)
			echo "Unsupported operating system: $(uname -s 2>/dev/null || printf 'unknown')" >&2
			exit 1
			;;
	esac

	DISTRO="$(printf '%s' "${DISTRO:0:1}" | tr '[:lower:]' '[:upper:]')${DISTRO:1}"
	echo "Detected operating system: $OS $DISTRO $VERSION"
}

# Run as root or with sudo privileges.
run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    else
        sudo "$@"
    fi
}

# Show command output while a step is running, then leave only its result behind.
run_step() {
	local description="$1"
	shift

	local command_status log_file tee_status use_alternate_screen=false
	local -a pipeline_status
	log_file="$(mktemp "${TMPDIR:-/tmp}/wac-bootstrap.XXXXXX")"

	if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]] && command -v tput >/dev/null 2>&1; then
		use_alternate_screen=true
		tput smcup
		tput clear
		printf 'Running: %s\n\n' "$description"
	fi

	if "$@" 2>&1 | tee "$log_file"; then
		pipeline_status=("${PIPESTATUS[@]}")
	else
		pipeline_status=("${PIPESTATUS[@]}")
	fi
	command_status="${pipeline_status[0]}"
	tee_status="${pipeline_status[1]}"

	if [[ "$use_alternate_screen" == true ]]; then
		tput rmcup
	fi

	if (( command_status == 0 && tee_status == 0 )); then
		rm -f "$log_file"
		printf '[OK] %s\n' "$description"
		return 0
	fi

	printf '[ERROR] %s (exit code %d)\n' "$description" "$command_status" >&2
	printf 'Log: %s\n' "$log_file" >&2
	return "$command_status"
}

# Install necessary packages based on the detected operating system and distribution.
install_packages() {
  case "$OS" in
		Darwin)
			echo "Detected Darwin (macOS). You may need to install Homebrew first."
      #brew install git curl
      ;;
    Linux)
			case "$DISTRO" in
				Ubuntu|Debian)
					echo "Detected Ubuntu/Debian. You may need to install packages using apt-get."
          run_as_root apt-get update
          run_as_root apt-get install -y git curl gpg

					# Download and verify the GitHub CLI signing key.
					local out fingerprints expected_fingerprints
					out=$(mktemp)
					curl -fsSL -o "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
					gpg --show-keys "$out"
					fingerprints=$(gpg --show-keys --with-colons "$out" | awk -F: '$1 == "pub" { primary=1; next } primary && $1 == "fpr" { print $10; primary=0 }' | sort)
					expected_fingerprints=$(printf '%s\n' \
						2C6106201985B60E6C7AC87323F3D4EA75716059 \
						7F38BBB59D064DBCB3D84D725612B36462313325 | sort)
					if [[ "$fingerprints" != "$expected_fingerprints" ]]; then
						echo "GitHub CLI signing key fingerprint verification failed." >&2
						rm -f "$out"
						return 1
					fi
					echo "GitHub CLI signing key fingerprints verified."

					# Add the GitHub CLI repository to the system's sources list.
					run_as_root install -D -m 0644 "$out" /etc/apt/keyrings/githubcli-archive-keyring.gpg
					rm -f "$out"
					echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | run_as_root tee /etc/apt/sources.list.d/github-cli.list > /dev/null
					
					# Update the package list and install the GitHub CLI.
					run_as_root apt-get update
					run_as_root apt-get install -y gh
          ;;
        *)
          echo "Paketinstallation für $DISTRO ist noch nicht eingerichtet." >&2
          return 1
          ;;
      esac
      ;;
  esac
}

# Authenticate for access to private GitHub repositories.
authenticate_github() {
	if ! command -v gh >/dev/null 2>&1; then
		echo "GitHub CLI (gh) is required. Install it before running the bootstrap." >&2
		return 1
	fi

	if gh auth status --hostname github.com >/dev/null 2>&1; then
		return 0
	fi

	if [[ -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]]; then
		echo "The provided GitHub token is invalid or lacks access to github.com." >&2
		return 1
	fi

	if [[ "$OS" == Linux && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
		printf 'Open https://github.com/login/device in a browser outside this container, enter the code shown below, then press Enter here.\n'
		GH_BROWSER=true gh auth login --hostname github.com --web --git-protocol https
	else
		gh auth login --hostname github.com --web --git-protocol https
	fi
}

# Clone or update the private repository
clone_or_update() {
	private_repo="grobdaniel/workstation-as-code"
	local_target="${local_target:-$HOME/Developer/github-workspace/private/workstation-as-code}"

	# Ensure the parent directory of the local target exists.
  if [[ ! -d "$(dirname "$local_target")" ]]; then
    mkdir -p "$(dirname "$local_target")"
  fi

	# Clone the repository if it doesn't exist, otherwise pull the latest changes.
  if [[ -d "$local_target/.git" ]]; then
    git -C "$local_target" pull --ff-only
  else
    gh repo clone "$private_repo" "$local_target"
  fi
}

# Main entry point for the bootstrap process.
main() {
	echo "Starting bootstrap process..."
	detect_os
	run_step "Install required packages" install_packages

	run_step "Authenticate with GitHub" authenticate_github
	run_step "Clone or update repository" clone_or_update
}

main "$@"