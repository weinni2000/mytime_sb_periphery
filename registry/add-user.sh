#!/bin/sh
# Add or update a registry user in registry/auth/htpasswd (bcrypt).
#   ./registry/add-user.sh <user>
# Asks for the password; restart the registry afterwards:
#   docker compose restart registry
set -eu

if [ $# -ne 1 ]; then
    echo "Usage: $0 <user>" >&2
    exit 1
fi

cd "$(dirname "$0")"
mkdir -p auth
touch auth/htpasswd

printf "Password for %s: " "$1"
stty -echo
read -r password
stty echo
echo

# Drop an existing entry for this user, then append the new hash.
grep -v "^$1:" auth/htpasswd > auth/htpasswd.tmp || true
docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$1" "$password" \
    >> auth/htpasswd.tmp
mv auth/htpasswd.tmp auth/htpasswd
echo "User $1 saved in registry/auth/htpasswd"
