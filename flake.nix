{
  description = "Linux Mod Organizer (LMO), native NixOS build";

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
          lmo = pkgs.rustPlatform.buildRustPackage {
            pname = "linux-mod-organizer";
            version = "unstable";
            src = lmo-src;

            # Assumes the repository has a root Cargo.lock and a Cargo
            # workspace exposing the lmo and lmo-gui binary targets.
            cargoLock.lockFile = "${lmo-src}/Cargo.lock";
            cargoBuildFlags = [ "--workspace" "--bins" ];

            nativeBuildInputs = with pkgs; [
              pkg-config
              makeWrapper
              wrapGAppsHook3
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

            # Runtime tools are not all required to compile LMO, but the
            # mod overlay and archive operations may call them.
            postInstall = ''
              for binary in lmo lmo-gui; do
                if [ -e "$out/bin/$binary" ]; then
                  wrapProgram "$out/bin/$binary" \
                    --prefix PATH : ${pkgs.lib.makeBinPath (with pkgs; [
                      fuse-overlayfs
                      git
                      p7zip
                      unar
                    ])}
                fi
              done
              test -x "$out/bin/lmo"
              test -x "$out/bin/lmo-gui"
            '';

            doCheck = false;

            meta = with pkgs.lib; {
              description = "Native Linux mod organizer with CLI and GUI";
              homepage = "https://codeberg.org/enoki/linux-mod-organizer";
              license = licenses.gpl3Plus;
              platforms = [ "x86_64-linux" ];
              mainProgram = "lmo-gui";
            };
          };
        in { default = lmo; lmo = lmo; }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/lmo-gui";
        };
        cli = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/lmo";
        };
      });
    };
}
