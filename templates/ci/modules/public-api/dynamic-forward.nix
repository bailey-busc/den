# Regression test for #575: dynamic home/host forwarding.
{ denTest, ... }:
{
  flake.tests.dynamic-forward = {

    test-nixpkgs-overlay-forward = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        nixpkgsClass =
          ctx:
          lib.optionalAttrs ((ctx ? host || ctx ? home) && !(ctx ? host && ctx ? user)) (
            { class, aspect-chain, ... }:
            den._.forward {
              each = [ (ctx.home or ctx.host) ];
              fromClass = _: "nixpkgs";
              intoClass = { class, ... }: class;
              intoPath = _: [ "nixpkgs" ];
              fromAspect = _: lib.head aspect-chain;
              adaptArgs = lib.id;
            }
          );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.includes = [
          den._.mutual-provider
          nixpkgsClass
        ];

        den.aspects.tux.provides.igloo = {
          nixpkgs.overlays = [
            (final: prev: {
              cowsay = prev.cowsay.overrideAttrs (oldAttrs: {
                passthru = oldAttrs.passthru or { } // {
                  hello = "world";
                };
              });
            })
          ];

          nixos =
            { pkgs, ... }:
            {
              users.users.tux.description = pkgs.cowsay.hello;
            };
        };

        expr = igloo.users.users.tux.description;
        expected = "world";
      }
    );

    test-explicit-identity-adapter-preserves-target-config = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        probeModule = {
          options.forward-probe = {
            target = lib.mkOption { type = lib.types.str; };
            copied = lib.mkOption { type = lib.types.str; };
          };
        };

        forwarded =
          { class, aspect-chain }:
          den._.forward {
            each = lib.singleton class;
            fromClass = _: "probe";
            intoClass = _: "nixos";
            intoPath = _: [ "forward-probe" ];
            fromAspect = _: lib.head aspect-chain;
            adaptArgs = lib.id;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          includes = [ forwarded ];
          nixos = {
            imports = [ probeModule ];
            forward-probe.target = "outer";
          };
          probe =
            { config, ... }:
            {
              copied = config.forward-probe.target;
            };
        };

        expr = igloo.forward-probe;
        expected = {
          target = "outer";
          copied = "outer";
        };
      }
    );

  };
}
