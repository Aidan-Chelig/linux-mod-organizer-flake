{
  description = "Linux Mod Organizer CLI (native Nix build)";

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
          runtimeTools = with pkgs; [
            fuse-overlayfs
            git
            p7zip
            unar
          ];
          lmo = pkgs.rustPlatform.buildRustPackage {
            pname = "linux-mod-organizer";
            version = "1.28.0";
            src = lmo-src;
            cargoLock.lockFile = "${lmo-src}/Cargo.lock";

            # The Cargo workspace contains an `lmo` binary, not `lmo-gui`.
            cargoBuildFlags = [ "--bin" "lmo" ];

            nativeBuildInputs = with pkgs; [
              pkg-config
              makeWrapper
            ];
            buildInputs = with pkgs; [
              gtk3
              webkitgtk_4_1
              glib
              gdk-pixbuf
              cairo
              pango
              libsoup_3
              openssl
              sqlite
            ];

            # Nix's Cargo hooks produced a target-triple subdirectory on
            # this system, rather than target/release/lmo.
            installPhase = ''
              runHook preInstall

              binary="target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/lmo"
              if [ ! -x "$binary" ]; then
                echo "Expected LMO binary missing: $binary" >&2
                find target -maxdepth 5 -type f -name lmo -print >&2
                exit 1
              fi

              install -Dm755 "$binary" "$out/bin/lmo"
              runHook postInstall
            '';

            postFixup = ''
              wrapProgram "$out/bin/lmo" \
                --prefix PATH : ${pkgs.lib.makeBinPath runtimeTools}
            '';

            doCheck = false;

            meta = with pkgs.lib; {
              description = "Linux Mod Organizer command-line interface";
              homepage = "https://codeberg.org/enoki/linux-mod-organizer";
              license = licenses.gpl3Plus;
              platforms = [ "x86_64-linux" ];
              mainProgram = "lmo";
            };
          };
        in {
          default = lmo;
          lmo = lmo;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/lmo";
        };
      });
    };
}
