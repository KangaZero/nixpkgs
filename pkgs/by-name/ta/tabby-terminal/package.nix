{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  makeDesktopItem,
  copyDesktopItems,
  nix-update-script,
  # Electron runtime deps
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxtst,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  wayland,
  xdg-utils,
  # Tabby native-module deps
  fontconfig,
  freetype,
  libsecret, # keytar: system keychain integration
}:
let
  archSuffix = {
    x86_64-linux = "x64";
    aarch64-linux = "arm64";
  };
in
stdenv.mkDerivation (
  finalAttrs:
  let
    suffix =
      archSuffix.${stdenv.hostPlatform.system}
        or (throw "tabby-terminal: unsupported platform ${stdenv.hostPlatform.system}");

    icon = fetchurl {
      url = "https://raw.githubusercontent.com/Eugeny/tabby/v${finalAttrs.version}/app/assets/logo.svg";
      hash = "sha256-w7RPcKRGLjTYNzj3NMQLYQVz6NFcBK2ITzoT0C4DA5k=";
    };
  in
  {
    pname = "tabby-terminal";
    version = "1.0.234";

    # Upstream ships prebuilt Electron release tarballs. Building from source
    # is impractical here: the release bundles native modules (node-pty,
    # keytar, russh, @serialport) in resources/app.asar.unpacked, ABI-locked to
    # the bundled Electron 38. Repackaging the tarball (à la discord) is the
    # realistic approach; swapping to the nixpkgs `electron_38` would risk
    # native-module ABI skew and needs a full source build to be safe.
    src = fetchurl {
      url = "https://github.com/Eugeny/tabby/releases/download/v${finalAttrs.version}/tabby-${finalAttrs.version}-linux-${suffix}.tar.gz";
      hash =
        {
          x64 = "sha256-K2zb0gr8PsC1Ml5wOjrdqIAOhUa9oV4Gr9n1esEmTC4=";
          arm64 = "sha256-45IEBedQ7bNBAsvbjuXCKc5dmBdmmmuaD/3doKBl94g=";
        }
        .${suffix};
    };

    sourceRoot = "tabby-${finalAttrs.version}-linux-${suffix}";

    nativeBuildInputs = [
      autoPatchelfHook
      copyDesktopItems
      makeWrapper
      wrapGAppsHook3
    ];

    buildInputs = [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      fontconfig
      freetype
      gdk-pixbuf
      glib
      gsettings-desktop-schemas
      gtk3
      libdrm
      libgbm
      libglvnd
      libsecret
      libx11
      libxcb
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxkbcommon
      libxrandr
      libxrender
      libxscrnsaver
      libxtst
      mesa
      nspr
      nss
      pango
      stdenv.cc.cc.lib # libstdc++.so.6
      systemd
      wayland
    ];

    desktopItems = [
      (makeDesktopItem {
        name = "tabby";
        exec = "tabby %U";
        icon = "tabby";
        desktopName = "Tabby";
        genericName = "Terminal Emulator";
        comment = "A terminal for a modern age";
        categories = [
          "System"
          "TerminalEmulator"
        ];
        keywords = [
          "ssh"
          "serial"
          "telnet"
          "terminal"
        ];
        startupWMClass = "Tabby";
      })
    ];

    # libvk_swiftshader.so: bundled software-GL fallback, no nixpkgs counterpart.
    # libc.musl-x86_64.so.1: @serialport ships glibc + musl prebuilds; the musl
    #   build is unused on glibc systems but autoPatchelf still scans it.
    autoPatchelfIgnoreMissingDeps = [
      "libvk_swiftshader.so"
      "libc.musl-x86_64.so.1"
    ];

    # Prebuilt vendor binaries + the Electron blob must not be stripped.
    dontStrip = true;

    # Wrap manually below so the Wayland/sandbox flags and the GApps
    # environment (GSettings schemas, GIO modules) land on one wrapper.
    dontWrapGApps = true;

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -d "$out/opt/tabby-terminal"
      cp -r . "$out/opt/tabby-terminal/"

      # chrome-sandbox needs setuid root, which Nix cannot set at install time.
      # Drop it and run with --no-sandbox; on NixOS the sandbox can instead be
      # provided system-wide via security.chromiumSuidSandbox.enable.
      rm -f "$out/opt/tabby-terminal/chrome-sandbox"

      install -Dm444 "${icon}" "$out/share/icons/hicolor/scalable/apps/tabby.svg"

      runHook postInstall
    '';

    # Wrap in preFixup, not installPhase: wrapGAppsHook3 only finishes
    # populating gappsWrapperArgs (GSettings schema XDG_DATA_DIRS, GIO modules)
    # during preFixup, so wrapping any earlier would miss the schema dirs and
    # cause "Settings schema ... is not installed" aborts (e.g. file chooser).
    preFixup = ''
      install -d "$out/bin"
      # autoPatchelf already sets an RPATH covering the bundled sibling libs,
      # so no LD_LIBRARY_PATH here — it would otherwise leak into every shell
      # spawned inside the terminal (node-pty children).
      makeWrapper "$out/opt/tabby-terminal/tabby" "$out/bin/tabby" \
        "''${gappsWrapperArgs[@]}" \
        --add-flags "--no-sandbox" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations}}" \
        --prefix PATH : "${lib.makeBinPath [ xdg-utils ]}"
    '';

    passthru.updateScript = nix-update-script { };

    meta = {
      description = "Terminal emulator, SSH, serial and Telnet client";
      longDescription = ''
        Tabby is a highly configurable terminal emulator, SSH, serial and Telnet
        client for Linux (also Windows and macOS). It features a tabbed interface,
        built-in SSH key manager, SFTP panel, serial port client, and an extensible
        plugin ecosystem.
      '';
      homepage = "https://tabby.sh";
      changelog = "https://github.com/Eugeny/tabby/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [ kangazero ];
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      mainProgram = "tabby";
    };
  }
)
