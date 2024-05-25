{writeShellApplication, ...}:
writeShellApplication {
  name = "update-gradle-version";
  text = builtins.readFile ./update-gradle-version.bash;
}
