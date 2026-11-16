# The release archive, not a source build: spinrail's toolchain clones
# spinel and tep while building, which a Nix build can't do.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  darwin,
  openssl,
  sqlite,
  release,
  platform,
}:

stdenv.mkDerivation {
  pname = "localito";
  inherit (release) version;

  src = fetchurl {
    url = "https://github.com/ceritium/localito/releases/download/v${release.version}/localito-v${release.version}-${platform}.tar.gz";
    sha256 = release.sha256.${platform};
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = [
    openssl
    sqlite
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/localito $out/bin
    cp -r . $out/share/localito
    ln -s $out/share/localito/bin/localito $out/bin/localito
    runHook postInstall
  '';

  # The macOS build links Homebrew's OpenSSL; point it at nixpkgs' and re-sign.
  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    server=$out/share/localito/libexec/localito-server
    for lib in libssl.3.dylib libcrypto.3.dylib; do
      install_name_tool -change /opt/homebrew/opt/openssl@3/lib/$lib ${lib.getLib openssl}/lib/$lib $server
    done
    ${darwin.sigtool}/bin/codesign -f -s - $server
  '';

  meta = {
    description = "Browse and edit a Rails app's i18n YAML files in the browser";
    homepage = "https://github.com/ceritium/localito";
    mainProgram = "localito";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
