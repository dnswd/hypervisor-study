{
  description = "A Nix-flake-based Rust development environment";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.*.tar.gz";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, rust-overlay }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default self.overlays.default ];
        };
      });
    in
    {
      overlays.default = final: prev: {
        rustToolchain =
          let
            rust = prev.rust-bin;
          in
          if builtins.pathExists ./rust-toolchain.toml then
            rust.fromRustupToolchainFile ./rust-toolchain.toml
          else if builtins.pathExists ./rust-toolchain then
            rust.fromRustupToolchainFile ./rust-toolchain
          else
            rust.stable.latest.default.override {
              extensions = [ "rust-src" "rustfmt" ];
            };

        bochs-tandasat = final.stdenv.mkDerivation {
          pname = "bochs";
          version = "tandasat-fork";

          # src = ./project/Bochs/bochs; # Path to the Bochs source
          src = final.fetchFromGitHub {
            owner = "tandasat";
            repo = "Bochs";
            rev = "gcc";
            sha256 = "sha256-n5KEC8IsXmSP/tjb+Y5KJsW6HEdCtCBnlfdf5g6ahK0=";
          };

          nativeBuildInputs = [
            final.libtool
            final.autoconf
            final.automake
            final.bison
            final.flex
            final.cmake
          ];

          buildInputs = [
            final.ncurses
            final.xorg.libX11
            final.xorg.libXrandr
            final.xorg.libXinerama
            final.xorg.libXcursor
          ];

          configurePhase = # sh
            ''
              pushd bochs || return 1
              sh .conf.linux
            '';

          buildPhase = ''
            sh .conf.linux
            make
          '';

          installPhase = # sh
            ''
              make install \
              prefix=$out \
              exec_prefix=$out \
              bindir=$out/bin \
              libdir=$out/lib \
              plugdir=$out/lib/bochs/plugins \
              mandir=$out/share/man \
              docdir=$out/share/doc/bochs \
              sharedir=$out/share/bochs
            '';

          postInstall = ''
            # Set correct plugin path
            sed -i "s|/usr/local/lib/bochs/plugins|$out/lib/bochs/plugins|g" $out/bin/bochs
            
            # Set correct shared resource path
            sed -i "s|/usr/local/share/bochs|$out/share/bochs|g" $out/bin/bochs
          '';
        };
      };

      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            rustToolchain
            openssl
            pkg-config
            cargo-deny
            cargo-edit
            cargo-watch
            rust-analyzer

            # requirements
            p7zip
            inetutils
          ];

          buildInputs = [ pkgs.bochs-tandasat ];

          # shellHook = ''
          #   export PATH=$PATH:${pkgs.bochs}/bin
          # '';

          shellHook = ''
            # Export LTDL_LIBRARY_PATH for Bochs plugins
            export LTDL_LIBRARY_PATH=${pkgs.bochs-tandasat}/lib/bochs/plugins
            # Export BXSHARE for Bochs shared resources
            export BXSHARE=${pkgs.bochs-tandasat}/share/bochs
          '';

          env = {
            # Required by rust-analyzer
            RUST_SRC_PATH = "${pkgs.rustToolchain}/lib/rustlib/src/rust/library";
          };
        };
      });
    };
}
