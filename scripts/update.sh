#!/bin/sh
# Update to the latest version from the repository this was installed from (same as re-running the install one-liner).
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
D=/media/developer/cleanyourtv
read repo ref < $D/source || { echo "no $D/source; run the install one-liner instead"; exit 1; }
curl -fsSL "https://raw.githubusercontent.com/$repo/$ref/install.sh" | sh -s -- "$@"
