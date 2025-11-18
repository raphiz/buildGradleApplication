if [ -e .attrs.sh ]; then source .attrs.sh; fi
source $stdenv/setup

curl=(
    curl
    --location
    --max-redirs 20
    --retry 3
    --disable-epsv
    --cookie-jar cookies
)

check_hash() {
    local file="$1"
    local expected_hash="$2"
    echo "~> $0 $1 $2 $3"
    # extract algorithm name from SRI-formatted hash
    hash_algorithm=$(echo "$expected_hash" | cut -d "-" -f 1)

    actual_hash=$(nix --extra-experimental-features nix-command hash file --type "$hash_algorithm" --sri "$file")
    if [ "$actual_hash" == "$expected_hash" ]; then
        return 0
    else
        echo "Hash does not match: expected $expected_hash - actual $actual_hash"
        return 1
    fi
}

# expected variables to be set:
name="${name:?}"
out="${out:?}"
url_prefixes="${url_prefixes:?}"
hash="${hash:?}"

url_suffix=$name
if [[ -n $module ]]; then
  url_suffix="$(< $module $jq -r '.variants | map(.files) | flatten | map(select(.'$hash_algo' == "'$hash_value'")) | (. + [{ url: "'$name'"}])[0].url')"
fi

for url_prefix in $url_prefixes; do
    url="$url_prefix/$url_suffix"
    echo "Downloading $name from $url"

    if "${curl[@]}" --retry 0 --connect-timeout "${NIX_CONNECT_TIMEOUT:-15}" \
        --fail --silent --show-error --head "$url" \
        --write-out "%{http_code}" --output /dev/null > code 2> log; then

            # Continue with download of partially downloaded file
            curl_exit_code=18;
            while [ $curl_exit_code -eq 18 ]; do
                if "${curl[@]}" -C - --fail "$url" --output "$out"; then
                    break
                else
                    curl_exit_code=$?;
                fi
            done

            if check_hash "$out" "$hash"; then
                echo "File $name successfully downloaded";
                exit 0;
            else
                rm "$out"
            fi
        else
            echo "error checking the existence of $url:"
            cat log
    fi
done

echo "File $name was not found with hash $hash on any of the given urls"
exit 1
