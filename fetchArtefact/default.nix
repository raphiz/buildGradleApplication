{
  lib,
  buildPackages,
  stdenvNoCC,
  curl,
  nix,
  cacert,
}: {
  # A list of URLs specifying alternative download locations. They are tried in order.
  urls,
  # SRI hash.
  hash,
  # Name of the file.
  name,
}:
stdenvNoCC.mkDerivation {
  inherit name hash;
  outputHash = hash;
  outputHashMode = "flat";

  builder = ./builder.bash;
  nativeBuildInputs = [curl nix];
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  inherit urls;

  # Doing the download on a remote machine just duplicates network
  # traffic, so don't do that
  preferLocalBuild = true;
}
