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
            OVMFFull
          ];

          buildInputs = [ pkgs.bochs-tandasat ];

          # shellHook = ''
          #   export PATH=$PATH:${pkgs.bochs}/bin
          # '';

          shellHook = ''
            # mkdir -p /usr/share/ovmf
            # ln -sf ${pkgs.OVMFFull}/FV/OVMF.fd /usr/share/ovmf/OVMF.fd
            #
            # mkdir -p /usr/local/share/bochs
            # ln -sf ${pkgs.bochs-tandasat}/share/bochs/VGABIOS-lgpl-latest /usr/local/share/bochs/VGABIOS-lgpl-latest
            #
            # ln -sf ${pkgs.OVMFFull}/FV/OVMF.fd /usr/share/ovmf/OVMF.fd
            # ln -sf ${pkgs.bochs-tandasat}/share/bochs/VGABIOS-lgpl-latest /usr/local/share/bochs/VGABIOS-lgpl-latest

            # Export LTDL_LIBRARY_PATH for Bochs plugins
            export LTDL_LIBRARY_PATH=${pkgs.bochs-tandasat}/lib/bochs/plugins
            # Export BXSHARE for Bochs shared resources
            export BXSHARE=${pkgs.bochs-tandasat}/share/bochs
            # Set OVMF path for Bochs
            # export BOCHS_ROM_PATH=${pkgs.OVMFFull}/FV/OVMF.fd

            # Backup the original config if it exists
            if [ -f "tests/bochs/linux_amd.bxrc" ]; then
              mv tests/bochs/linux_amd.bxrc test/bochs/linux_amd.bxrc.bak
            fi

            # Create a temporary modified config with correct paths
            mkdir -p tests/bochs
            cat > tests/bochs/linux_amd.bxrc <<EOF
            plugin_ctrl: biosdev=true, busmouse=false, e1000=false, es1370=false, extfpuirq=true, parallel=true, sb16=false, serial=true, speaker=false, unmapped=true, usb_ehci=false, usb_ohci=false, usb_uhci=false, usb_xhci=false, voodoo=false
            config_interface: textconfig
            display_library: nogui
            memory: host=1024, guest=1024
            romimage: file="${pkgs.OVMFFull}/FV/OVMF.fd", address=0xffe00000, options=none
            vgaromimage: file="${pkgs.bochs-tandasat}/share/bochs/VGABIOS-lgpl-latest"
            boot: disk
            floppy_bootsig_check: disabled=0
            floppya: type=1_44
            # no floppyb
            ata0: enabled=true, ioaddr1=0x1f0, ioaddr2=0x3f0, irq=14
            ata0-master: type=disk, path="samples/bochs_disk.img", mode=flat
            ata0-slave: type=none
            ata1: enabled=true, ioaddr1=0x170, ioaddr2=0x370, irq=15
            ata1-master: type=none
            ata1-slave: type=none
            ata2: enabled=false
            ata3: enabled=false
            optromimage1: file=none
            optromimage2: file=none
            optromimage3: file=none
            optromimage4: file=none
            optramimage1: file=none
            optramimage2: file=none
            optramimage3: file=none
            optramimage4: file=none
            pci: enabled=1, chipset=i440fx, slot1=none, slot2=none, slot3=none, slot4=none, slot5=none
            vga: extension=vbe, update_freq=5, realtime=1, ddc=builtin
            cpu: count=1, ips=20000000, model=ryzen, reset_on_triple_fault=0, cpuid_limit_winnt=0, ignore_bad_msrs=1, mwait_is_nop=0
            print_timestamps: enabled=0
            port_e9_hack: enabled=0
            private_colormap: enabled=0
            clock: sync=none, time0=local, rtc_sync=0
            # no cmosimage
            log: -
            logprefix: %d%e|
            debug: action=ignore
            info: action=report
            error: action=report
            panic: action=report
            keyboard: type=mf, serial_delay=250, paste_delay=100000, user_shortcut=none
            mouse: type=ps2, enabled=false, toggle=ctrl+mbutton
            com1: enabled=true, mode=socket-server, dev="localhost:14449"
            com2: enabled=false
            com3: enabled=false
            com4: enabled=false
            parport1: enabled=true, file=none
            parport2: enabled=false
            magic_break: enabled=0
            EOF

            # Clean up and restore original config on shell exit
            trap "rm -f tests/bochs/linux_amd.bxrc && mv tests/bochs/linux_amd.bxrc.bak tests/bochs/linux_amd.bxrc 2>/dev/null"
          '';

          env = {
            # Required by rust-analyzer
            RUST_SRC_PATH = "${pkgs.rustToolchain}/lib/rustlib/src/rust/library";
          };
        };
      });
    };
}
