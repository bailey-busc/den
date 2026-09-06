# Issue #645: two chained custom classes (`inner` -> `mid` -> `homeManager`)
# originally collided on the inner hop's `den.fwd."inner/mid/<path>"`
# declaration.
#
# The inner adapter still reaches the target indirectly through the `mid`
# bucket. The list assertions detect a second route owner without relying on an
# option declaration conflict.
{ denTest, ... }:
let
  shellOptionMarker = "den-forward-once";
  markerCount =
    options: builtins.length (builtins.filter (option: option == shellOptionMarker) options);

  # `inner` content lands at `programs.bash` of the `mid` class; `mid` merges
  # into `homeManager` wholesale.
  innerClass =
    den: lib:
    { class, aspect-chain }:
    den._.forward {
      each = lib.singleton class;
      fromClass = _: "inner";
      intoClass = _: "mid";
      intoPath = _: [
        "programs"
        "bash"
      ];
      fromAspect = _: lib.last aspect-chain;
      guard = _: true;
    };

  midClass =
    den: lib:
    { class, aspect-chain }:
    den._.forward {
      each = lib.singleton class;
      fromClass = _: "mid";
      intoClass = _: "homeManager";
      intoPath = _: [ ];
      fromAspect = _: lib.last aspect-chain;
    };
in
{
  flake.tests.deadbugs.issue-645-chained-forward-classes = {

    test-chained-forward-with-host-aspects = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          den._.host-aspects
          (innerClass den lib)
          (midClass den lib)
        ];

        den.aspects.chained.inner = {
          enable = true;
          shellOptions = [ shellOptionMarker ];
        };

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.chained ];

        expr = {
          enable = tuxHm.programs.bash.enable or "<stranded>";
          markerCount = markerCount tuxHm.programs.bash.shellOptions;
        };
        expected = {
          enable = true;
          markerCount = 1;
        };
      }
    );

    # Chained content defined on the host aspect: dropping the spawn's copy of
    # the inner adapter route must not strand what the projection carries.
    test-chained-forward-host-defined = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          den._.host-aspects
          (innerClass den lib)
          (midClass den lib)
        ];

        den.aspects.chained.inner = {
          enable = true;
          shellOptions = [ shellOptionMarker ];
        };

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.chained ];

        expr = {
          enable = tuxHm.programs.bash.enable or "<stranded>";
          markerCount = markerCount tuxHm.programs.bash.shellOptions;
        };
        expected = {
          enable = true;
          markerCount = 1;
        };
      }
    );

    # The same chain without the battery — no spawn, so this isolates the
    # chained-route collision from anything host-aspects contributes.
    test-chained-forward-without-host-aspects = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          (innerClass den lib)
          (midClass den lib)
        ];

        den.aspects.chained.inner.enable = true;

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.chained ];

        expr = tuxHm.programs.bash.enable or "<stranded>";
        expected = true;
      }
    );

  };
}
