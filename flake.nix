{
  description = "Armadarr - Media management stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pins the Bun used by the build, the dev shell, and CI.
    # Keep `@types/bun` and `packageManager` in package.json on the same version.
    bun-flake = {
      url = "github:antoine-bouteiller/bun-flake/v1.4.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    git-hooks,
    bun-flake,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    pkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [bun-flake.overlays.default];
      };

    # Production dependencies only, unpacked at their install paths from
    # the tarballs listed by `scripts/nix_deps.ts`.
    nodeModulesFor = pkgs:
      pkgs.runCommand "armadarr-node-modules" {} (
        pkgs.lib.concatMapStrings (dep: ''
          mkdir -p "$out/${dep.path}"
          tar -xzf ${pkgs.fetchurl {inherit (dep) url hash;}} -C "$out/${dep.path}" --strip-components=1
        '') (builtins.fromJSON (builtins.readFile ./nix/deps.json))
      );

    # JS tooling runs from node_modules so hooks use the versions pinned in
    # package.json.
    gitHooksFor = system:
      git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          commit-msg = {
            enable = true;
            name = "commit-msg";
            entry = "node_modules/.bin/devkit commit-msg";
            stages = ["commit-msg"];
          };
          alejandra = {
            enable = true;
            settings.verbosity = "quiet";
          };
          lockfile = {
            enable = true;
            name = "Check lockfile";
            entry = "bun install --frozen-lockfile --silent";
            pass_filenames = false;
            always_run = true;
          };
          lint = {
            enable = true;
            name = "oxlint";
            entry = "bunx oxlint --fix --fix-suggestions";
            files = "\\.(ts|tsx|js|mjs|cjs)$";
            excludes = ["^oxlint\\.config\\.ts$"];
          };
          format = {
            enable = true;
            name = "bun fmt";
            entry = "bun fmt";
            excludes = ["\\.(nix|lock|toml|svg|png)$" "(^|/)(LICENSE|\\.(envrc|gitignore|dockerignore))$"];
          };
          nix-deps = {
            enable = true;
            name = "Update nix/deps.json";
            entry = "bun scripts/nix_deps.ts";
            files = "^bun\\.lock$";
            pass_filenames = false;
          };
          knip = {
            enable = true;
            name = "knip";
            entry = "bun run knip";
            pass_filenames = false;
            always_run = true;
          };
          knip-production = {
            enable = true;
            name = "knip (production)";
            entry = "bun run knip:production";
            pass_filenames = false;
            always_run = true;
          };
        };
      };
  in
    {
      devShells = forAllSystems (system: let
        pkgs = pkgsFor system;
        gitHooks = gitHooksFor system;
      in {
        default = pkgs.mkShell {
          packages = [pkgs.bun pkgs.nodejs pkgs.alejandra] ++ gitHooks.enabledPackages;
          inherit (gitHooks) shellHook;
        };
      });

      packages = forAllSystems (system: let
        pkgs = pkgsFor system;
        nodeModules = nodeModulesFor pkgs;

        # `bun build --compile` bundles the server and, through the HTML
        # import, the client into one standalone binary.
        armadarr = pkgs.stdenv.mkDerivation {
          pname = "armadarr";
          version = "unstable";

          src = pkgs.lib.cleanSource ./.;

          nativeBuildInputs = [pkgs.bun];

          buildPhase = ''
            runHook preBuild
            ln -s ${nodeModules}/node_modules node_modules
            bun build --compile --production --react-compiler src/index.ts --outfile armadarr
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 armadarr "$out/bin/armadarr"
            runHook postInstall
          '';

          # Stripping drops the bundle Bun appends to the compiled executable.
          dontStrip = true;

          # The NixOS module's ExecStart relies on this.
          meta.mainProgram = "armadarr";
        };
      in {
        default = armadarr;
        armadarr = armadarr;
      });
    }
    // {
      nixosModules.default = {
        config,
        lib,
        pkgs,
        ...
      }: let
        cfg = config.services.armadarr;
      in {
        options.services.armadarr = {
          enable = lib.mkEnableOption "armadarr media management service";
          package = lib.mkOption {
            type = lib.types.package;
            default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
            description = "The armadarr package to use.";
          };
          dataDir = lib.mkOption {
            type = lib.types.path;
            default = "/var/lib/armadarr";
            description = "Directory for armadarr data files.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 3000;
            description = "Port for armadarr to listen on.";
          };
          user = lib.mkOption {
            type = lib.types.str;
            default = "armadarr";
            description = "User account under which Armadarr runs";
          };
          group = lib.mkOption {
            type = lib.types.str;
            default = "armadarr";
            description = "Group under which Armadarr runs";
          };
        };

        config = lib.mkIf cfg.enable {
          users.users = lib.mkIf (cfg.user == "armadarr") {
            armadarr = {
              group = cfg.group;
              home = cfg.dataDir;
              isSystemUser = true;
            };
          };

          users.groups = lib.mkIf (cfg.group == "armadarr") {
            armadarr = {};
          };

          systemd.services.armadarr = {
            description = "Armadarr media management service";
            after = ["network.target"];
            wantedBy = ["multi-user.target"];

            serviceConfig = {
              ExecStart = "${cfg.package}/bin/armadarr";

              StateDirectory = "armadarr";
              WorkingDirectory = cfg.dataDir;
              UMask = "002";

              User = cfg.user;
              Group = cfg.group;
              Restart = "on-failure";

              CapabilityBoundingSet = "";
              NoNewPrivileges = true;
              PrivateDevices = true;
              ProtectHome = true;
            };

            environment = {
              PORT = toString cfg.port;
              NODE_ENV = "production";
            };
          };
        };
      };
    };
}
