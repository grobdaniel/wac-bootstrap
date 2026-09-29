#!/usr/bin/env bash

set -euo pipefail

echo "Starting bootstrap process..."

# Detect the operating system and Linux distribution.
os=""
distribution=""
case "$(uname -s 2>/dev/null || printf 'Unknown')" in
	Linux)
		os="Linux"
		if [[ -r /etc/os-release ]]; then
			# shellcheck disable=SC1091
			source /etc/os-release
			distribution="${PRETTY_NAME:-${NAME:-Linux}}"
		else
			distribution="Linux"
		fi
		;;
	Darwin)
		os="macOS"
		distribution="macOS"
		;;
	MINGW*|MSYS*|CYGWIN*)
		os="Windows"
		distribution="Windows"
		;;
	*)
		echo "Unsupported operating system: $(uname -s 2>/dev/null || printf 'unknown')" >&2
		exit 1
		;;
esac

echo "Detected operating system: $os $distribution"
