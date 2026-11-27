{
  description = "Armadarr - Media management stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    git-hooks,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    pkgsFor = system: import nixpkgs {inherit system;};

    # JS tooling runs from app/frontend/node_modules so hooks use the versions
    # pinned in its package.json.
    gitHooksFor = system:
      git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          commit-msg = {
            enable = true;
            name = "commit-msg";
            entry = "app/frontend/node_modules/.bin/devkit commit-msg";
            stages = ["commit-msg"];
          };
          alejandra = {
            enable = true;
            settings.verbosity = "quiet";
          };
          lockfile = {
            enable = true;
            name = "Check lockfile";
            entry = "pnpm --dir app/frontend install --frozen-lockfile --silent";
            pass_filenames = false;
            always_run = true;
          };
          vp-staged = {
            enable = true;
            name = "vp staged";
            entry = "pnpm --dir app/frontend exec vp staged";
            pass_filenames = false;
            always_run = true;
          };
          # vp staged formats app/frontend only; this formats the rest of the repository.
          oxfmt = {
            enable = true;
            name = "oxfmt";
            entry = "app/frontend/node_modules/.bin/oxfmt -c app/frontend/node_modules/@antoine-bouteiller/devkit/dist/fmt.json";
            files = "\\.(md|ya?ml|json5?)$";
            excludes = ["^app/frontend/" "^vendor/"];
            # The built-in oxfmt hook limits itself to JavaScript and TypeScript.
            types_or = [];
          };
          svelte-check = {
            enable = true;
            name = "svelte-check";
            entry = "pnpm --dir app/frontend run check:svelte";
            files = "^app/frontend/.*\\.(ts|svelte)$";
            pass_filenames = false;
          };
          golangci-lint = {
            enable = true;
            name = "golangci-lint";
            entry = "golangci-lint run --fix";
            files = "(\\.go|^go\\.(mod|sum))$";
            pass_filenames = false;
          };
          buf = {
            enable = true;
            name = "buf lint and generate";
            entry = "sh -c 'buf lint && buf generate'";
            files = "^(proto/|buf\\.)";
            pass_filenames = false;
          };
          knip = {
            enable = true;
            name = "knip";
            entry = "pnpm --dir app/frontend knip";
            pass_filenames = false;
            always_run = true;
          };
          knip-production = {
            enable = true;
            name = "knip (production)";
            entry = "pnpm --dir app/frontend knip:production";
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
          packages = [pkgs.go pkgs.golangci-lint pkgs.buf pkgs.nodejs pkgs.pnpm pkgs.just pkgs.alejandra] ++ gitHooks.enabledPackages;
          inherit (gitHooks) shellHook;
        };
      });

      packages = forAllSystems (system: let
        pkgs = pkgsFor system;
        inherit (pkgs) lib;

        pnpmLock = pkgs.callPackage ./nix/pnpm-lock.nix {} ./app/frontend/pnpm-lock.yaml;

        web = pkgs.stdenvNoCC.mkDerivation {
          pname = "armadarr-web";
          version = "unstable";

          src = lib.fileset.toSource {
            root = ./app/frontend;
            fileset = lib.fileset.unions [
              ./app/frontend/package.json
              ./app/frontend/pnpm-lock.yaml
              ./app/frontend/pnpm-workspace.yaml
              ./app/frontend/tsconfig.json
              ./app/frontend/vite.config.ts
              ./app/frontend/svelte.config.js
              ./app/frontend/index.html
              ./app/frontend/assets
              ./app/frontend/src
            ];
          };

          nativeBuildInputs = [pkgs.nodejs pkgs.pnpm];

          configurePhase = ''
            runHook preConfigure
            export HOME=$TMPDIR
            export pnpm_config_store_dir=$TMPDIR/pnpm-store
            export pnpm_config_pm_on_fail=ignore
            export pnpm_config_trust_lockfile=true
            export pnpm_config_update_notifier=false
            export pnpm_config_reporter=append-only
            cp --no-preserve=mode ${pnpmLock} pnpm-lock.yaml
            pnpm install --offline --frozen-lockfile --ignore-scripts
            patchShebangs node_modules/{*,.*}
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            pnpm exec vp build
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            cp -r dist/client "$out"
            runHook postInstall
          '';
        };

        # The client is embedded through app/frontend/embed.go, so the server is one
        # static binary.
        armadarr = pkgs.buildGoModule {
          pname = "armadarr";
          version = "unstable";

          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./go.mod
              ./go.sum
              ./vendor
              (lib.fileset.fileFilter (file: file.hasExt "go") ./app/backend)
              ./app/frontend/embed.go
              ./app/frontend/dist/.gitkeep
            ];
          };

          vendorHash = null;
          subPackages = ["app/backend/cmd/armadarr"];
          env.CGO_ENABLED = 0;
          ldflags = ["-s" "-w"];

          preBuild = ''
            cp -r ${web} app/frontend/dist/client
          '';

          passthru = {inherit web;};

          # The NixOS module's ExecStart relies on this.
          meta.mainProgram = "armadarr";
        };
      in {
        default = armadarr;
        inherit armadarr web;
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
            };
          };
        };
      };
    };
}
