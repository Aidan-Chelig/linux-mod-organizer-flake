{
  description = "Linux Mod Organizer — native CLI and Tauri GUI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lmo-src = {
      url = "git+https://codeberg.org/enoki/linux-mod-organizer";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, lmo-src }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          inherit (pkgs) lib;

          runtimeTools = with pkgs; [
            fuse-overlayfs
            git
            p7zip
            unar
          ];

          cli = pkgs.rustPlatform.buildRustPackage {
            pname = "linux-mod-organizer-cli";
            version = "1.28.0";
            src = lmo-src;
            cargoLock.lockFile = "${lmo-src}/Cargo.lock";
            cargoBuildFlags = [ "--bin" "lmo" ];

            nativeBuildInputs = with pkgs; [ pkg-config makeWrapper ];
            buildInputs = with pkgs; [
              gtk3 webkitgtk_4_1 glib gdk-pixbuf cairo pango
              libsoup_3 openssl sqlite
            ];


            installPhase = ''
              runHook preInstall
              install -Dm755 \
                target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/lmo \
                "$out/bin/lmo"
              runHook postInstall
            '';

            postFixup = ''
              wrapProgram "$out/bin/lmo" \
                --prefix PATH : ${lib.makeBinPath runtimeTools}
            '';

            doCheck = false;
            meta = with lib; {
              description = "Linux Mod Organizer CLI";
              homepage = "https://codeberg.org/enoki/linux-mod-organizer";
              license = licenses.gpl3Plus;
              mainProgram = "lmo";
              platforms = [ "x86_64-linux" ];
            };
          };

          # SvelteKit frontend, packaged separately so Cargo doesn't need npm/network.
          frontend = pkgs.buildNpmPackage {
            pname = "linux-mod-organizer-frontend";
            version = "1.28.0";
            # Fetch only the frontend subtree. fetchNpmDeps needs the
            # package-lock.json at its source root.
            src = "${lmo-src}/gui";

            # Replace this after the first build reports the expected hash.
            npmDepsHash = "sha256-pN/nwaaMpOVu0rRMsFjIUPkWW5LrQ9gkFx5OR+DeVLU=";

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/build"
              cp -r build/. "$out/build/"
              runHook postInstall
            '';
          };

          gui = pkgs.rustPlatform.buildRustPackage {
            pname = "linux-mod-organizer-gui";
            version = "1.28.0";
            src = lmo-src;

            # This is an independent Cargo workspace, not a root workspace binary.
            cargoRoot = "gui/src-tauri";
            buildAndTestSubdir = "gui/src-tauri";
            cargoLock.lockFile = "${lmo-src}/gui/src-tauri/Cargo.lock";
            cargoBuildFlags = [
              "--bin" "lmo-gui"
              "--features" "tauri/custom-protocol"
            ];

            RUSTFLAGS = "-C link-arg=-lstdc++";

            postPatch = ''
              mkdir -p gui/build
              cp -r ${frontend}/build/. gui/build/
            '';

            nativeBuildInputs = with pkgs; [
              pkg-config
              makeWrapper
              wrapGAppsHook3
            ];
            buildInputs = with pkgs; [
              gtk3
              webkitgtk_4_1
              libsoup_3
              glib
              glib-networking
              gdk-pixbuf
              cairo
              pango
              openssl
              sqlite
              librsvg
            ];

            installPhase = ''
              runHook preInstall
              binary=$(find . -type f -path '*/release/lmo-gui' -perm /111 -print -quit)
              if [ -z "$binary" ]; then
                echo "Could not find the compiled lmo-gui binary" >&2
                find . -type f -name 'lmo-gui*' -print >&2
                exit 1
              fi
              install -Dm755 "$binary" "$out/bin/lmo-gui"
              runHook postInstall
            '';

            # Let the GTK wrapper add runtime environment variables.
            preFixup = ''
              gappsWrapperArgs+=(
                --prefix PATH : ${lib.makeBinPath runtimeTools}
              )
            '';

            doCheck = false;
            meta = with lib; {
              description = "Linux Mod Organizer Tauri desktop GUI";
              homepage = "https://codeberg.org/enoki/linux-mod-organizer";
              license = licenses.gpl3Plus;
              mainProgram = "lmo-gui";
              platforms = [ "x86_64-linux" ];
            };
          };

          combined = pkgs.symlinkJoin {
            name = "linux-mod-organizer-1.28.0";
            paths = [ cli gui ];
          };
        in {
          default = combined;
          combined = combined;
          cli = cli;
          gui = gui;
          lmo = cli;
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.gui}/bin/lmo-gui";
        };
        gui = {
          type = "app";
          program = "${self.packages.${system}.gui}/bin/lmo-gui";
        };
        cli = {
          type = "app";
          program = "${self.packages.${system}.cli}/bin/lmo";
        };
      });
    };
}
