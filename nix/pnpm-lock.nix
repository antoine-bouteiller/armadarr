# Rewrites pnpm-lock.yaml so each package pnpm installs on the host resolves to
# a fetchurl of its tarball, checked against the lockfile's own integrity hash.
# `pnpm store add` files tarballs under a different key, so offline installs
# only find them through `file:` resolutions.
{
  lib,
  stdenv,
  fetchurl,
  writeText,
}: lockFile: let
  text = builtins.readFile lockFile;

  inherit (lib) elemAt hasPrefix head removePrefix removeSuffix splitString;

  # Nix has no YAML parser. This one only reads the block-mapping subset that
  # pnpm writes: 2-space indents, single-quoted keys, flow `{…}` and `[…]` values.
  # pnpm 12 writes its own pin as a first document; the project lockfile is the last.
  doc = lib.last (splitString "\n---\n" ("\n" + text));
  lines = builtins.filter (l: l != "" && !(hasPrefix "#" l)) (splitString "\n" doc);

  indent = l: builtins.stringLength (head (builtins.match "( *).*" l));
  unquote = s: let
    m = builtins.match "'(.*)'" s;
  in
    if m == null
    then s
    else head m;
  splitKV = l: let
    m = builtins.match "('[^']*'|[^ ]+):( (.*))?" (lib.trim l);
  in
    if m == null
    then throw "pnpm-lock.nix: cannot parse line: ${l}"
    else {
      key = unquote (elemAt m 0);
      value = elemAt m 2;
    };
  flow = v:
    if v == null
    then null
    else if hasPrefix "{" v
    then
      lib.listToAttrs (map (kv: let
        p = splitKV kv;
      in
        lib.nameValuePair p.key (unquote p.value))
      (splitString ", " (removeSuffix "}" (removePrefix "{" v))))
    else if hasPrefix "[" v
    then map unquote (splitString ", " (removeSuffix "]" (removePrefix "[" v)))
    else unquote v;
  block = ls:
    if ls == []
    then {}
    else let
      h = head ls;
      rest = lib.tail ls;
      n = lib.lists.findFirstIndex (l: indent l <= indent h) (builtins.length rest) rest;
      children = lib.take n rest;
      kv = splitKV h;
    in
      {
        ${kv.key} =
          if children == []
          then flow kv.value
          else block children;
      }
      // block (lib.drop n rest);

  lock = block lines;

  platform = with stdenv.hostPlatform; {
    os =
      if isLinux
      then "linux"
      else if isDarwin
      then "darwin"
      else throw "pnpm-lock.nix: unsupported OS";
    cpu =
      if isx86_64
      then "x64"
      else if isAarch64
      then "arm64"
      else throw "pnpm-lock.nix: unsupported CPU";
    libc =
      if isMusl
      then "musl"
      else "glibc";
  };
  # npm semantics: a `!value` entry excludes it, positive entries form an allowlist.
  allows = field: pkg: let
    values = pkg.${field} or [];
    allowed = builtins.filter (v: !(hasPrefix "!" v)) values;
  in
    !(builtins.elem "!${platform.${field}}" values) && (allowed == [] || builtins.elem platform.${field} allowed);
  forHost = pkg: allows "os" pkg && allows "cpu" pkg && (!stdenv.hostPlatform.isLinux || allows "libc" pkg);

  fetch = key: pkg: let
    at = lib.stringLength key - lib.stringLength (lib.last (splitString "@" key)) - 1;
    name = builtins.substring 0 at key;
    version = builtins.substring (at + 1) (-1) key;
  in
    fetchurl {
      url = "https://registry.npmjs.org/${name}/-/${lib.last (splitString "/" name)}-${version}.tgz";
      hash = pkg.resolution.integrity;
    };

  resolutions = lib.mapAttrsToList (key: pkg: {
    from = "resolution: {integrity: ${pkg.resolution.integrity}}";
    to = "resolution: {integrity: ${pkg.resolution.integrity}, tarball: 'file:${fetch key pkg}'}";
  }) (lib.filterAttrs (_: forHost) lock.packages);
in
  writeText "pnpm-lock.yaml" (builtins.replaceStrings (map (r: r.from) resolutions) (map (r: r.to) resolutions) text)
