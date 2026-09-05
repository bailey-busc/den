# Regression: a context-aware custom-class forward must not expose Den's
# collision-validator metadata as options below the forwarding target.
{ denTest, ... }:
let
  forwardedClass =
    den: lib:
    { class, aspect-chain }:
    den._.forward {
      each = lib.singleton true;
      fromClass = _: "zed";
      intoClass = _: "homeManager";
      intoPath = _: [
        "programs"
        "zed-editor"
      ];
      fromAspect = _: lib.head aspect-chain;
      guard = { config, ... }: _: lib.mkIf config.programs.zed-editor.enable;
    };
in
{
  flake.tests.deadbugs.forward-module-metadata = {
    test-context-aware-forward-drops-module-metadata = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          den._.host-aspects
          (forwardedClass den lib)
        ];

        den.aspects.zed-default = {
          zed =
            { host, ... }:
            {
              defaultEditor = true;
            };
        };

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux = {
          includes = [ den.aspects.zed-default ];
          homeManager.programs.zed-editor.enable = true;
        };

        expr = tuxHm.programs.zed-editor.defaultEditor;
        expected = true;
      }
    );
  };
}
