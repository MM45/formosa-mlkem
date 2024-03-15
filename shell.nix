{ pkgs ?
    import (fetchTarball {
      url = https://github.com/NixOS/nixpkgs/archive/53fbe41cf76b6a685004194e38e889bc8857e8c2.tar.gz;
      sha256 = "sha256:1fyc4kbhv7rrfzya74yprvd70prlcsv56b7n0fv47kn7rznvvr2b";
    }) {}
, full ? true
}:

with pkgs;

let
  oc = ocaml-ng.ocamlPackages_4_14;
  why = why3.override {
    ocamlPackages = oc;
    ideSupport = false;
    coqPackages = { coq = null; flocq = null; };
  };
  ecVersion = "a8274feb63b62d281db350cd6dd8940c69aca835";
  ec = (easycrypt.overrideAttrs (_: {
    src = fetchFromGitHub {
      owner = "EasyCrypt";
      repo = "easycrypt";
      rev = ecVersion;
      hash = "sha256-Rbs3alnnnDPbKrAqPq1pj/kedHWC+PvPFES4d+V8EAk=";
    };
    postPatch = ''
      substituteInPlace dune-project --replace '(name easycrypt)' '(name easycrypt)(version ${ecVersion})'
    '';
  })).override {
    ocamlPackages = oc;
    why3 = why;
  };
  altergo = callPackage ./config/alt-ergo.nix { ocamlPackages = oc; } ;
in

mkShell ({
  JASMINC = "${jasmin-compiler.bin}/bin/jasminc";
} // lib.optionalAttrs full {
  packages = [
    ec
    altergo
    cvc4
    z3
  ];

  EC_RDIRS = "Jasmin:${jasmin-compiler.lib}/lib/jasmin/easycrypt";
})