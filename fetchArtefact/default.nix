{
  stdenvNoCC,
  curl,
  nix,
  cacert,
  jq,
  fetchurl
}: {
  # A list of URLs specifying alternative download locations. They are tried in order.
  url_prefixes,
  # SRI hash.
  hash,
  # Name of the file.
  name,
  # path
  path,
  # hash in undecoded form
  hash_algo,
  hash_value,
  # module json file that can contain content with url/name mappings
  module ? null,
}:
stdenvNoCC.mkDerivation {
  inherit name hash;
  outputHash = hash;
  outputHashMode = "flat";

  builder = ./builder.bash;
  nativeBuildInputs = [curl nix];
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  inherit url_prefixes module hash_algo hash_value;
  jq = "${jq}/bin/jq";

  # Doing the download on a remote machine just duplicates network
  # traffic, so don't do that
  preferLocalBuild = true;
}
