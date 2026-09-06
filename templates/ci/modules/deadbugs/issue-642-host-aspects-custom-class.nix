# Discussion #642: a custom class defined via `_.forward` originally
# double-emitted its content with the `host-aspects` battery and produced an
# "already declared" conflict on `den.fwd."<aspect>/<class>/<path>"`.
#
# Nested adapters no longer declare that option, but the route still needs one
# owner. The list assertions detect silent double materialization.
{ denTest, ... }:
let
  countAudioRecorder =
    plugins: builtins.length (builtins.filter (plugin: plugin.name == "audio-recorder") plugins);

  # One definition, threaded per test — each `denTest` gets its own `den`/`lib`.
  obsidianClass =
    den: lib:
    { class, aspect-chain }:
    den._.forward {
      each = lib.singleton class;
      fromClass = _: "obsidian";
      intoClass = _: "homeManager";
      intoPath = _: [
        "programs"
        "obsidian"
      ];
      fromAspect = _: lib.last aspect-chain;
      guard = { options, ... }: options ? programs.obsidian;
    };
in
{
  flake.tests.deadbugs.issue-642-host-aspects-custom-class = {

    # The reported shape: user-defined content through the custom class, with
    # the battery on.
    test-custom-class-with-host-aspects = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          den._.host-aspects
          (obsidianClass den lib)
        ];

        den.aspects.obsidian = {
          obsidian = {
            enable = true;
            defaultSettings.corePlugins = [ "audio-recorder" ];
          };
        };

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.obsidian ];

        expr = {
          enable = tuxHm.programs.obsidian.enable;
          audioRecorderCount = countAudioRecorder tuxHm.programs.obsidian.defaultSettings.corePlugins;
        };
        expected = {
          enable = true;
          audioRecorderCount = 1;
        };
      }
    );

    # The custom class's content lives on the HOST aspect and reaches the user
    # only through host-aspects — the projection the duplicate-suppression must
    # not strand.
    test-host-defined-custom-class-projects = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          den._.host-aspects
          (obsidianClass den lib)
        ];

        den.aspects.obsidian = {
          obsidian = {
            enable = true;
            defaultSettings.corePlugins = [ "audio-recorder" ];
          };
        };

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.obsidian ];

        expr = {
          enable = tuxHm.programs.obsidian.enable;
          audioRecorderCount = countAudioRecorder tuxHm.programs.obsidian.defaultSettings.corePlugins;
        };
        expected = {
          enable = true;
          audioRecorderCount = 1;
        };
      }
    );

    # Suppressing the spawn's copy leaves one owner for the adapter route. That
    # owner must still reach every user on the host, not only the first.
    test-host-defined-custom-class-reaches-every-user = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.default.includes = [
          den._.host-aspects
          (obsidianClass den lib)
        ];

        den.aspects.obsidian = {
          obsidian.enable = true;
        };

        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.includes = [ den.aspects.obsidian ];

        expr = {
          tux = igloo.home-manager.users.tux.programs.obsidian.enable or "<missing>";
          pingu = igloo.home-manager.users.pingu.programs.obsidian.enable or "<missing>";
        };
        expected = {
          tux = true;
          pingu = true;
        };
      }
    );

    # CONTROL: same custom class without the host-aspects battery — the one
    # shape that stayed green while the bug was live, isolating the battery as
    # the trigger.
    test-custom-class-without-host-aspects = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          (obsidianClass den lib)
        ];

        den.aspects.obsidian = {
          obsidian.enable = true;
        };

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.obsidian ];

        expr = tuxHm.programs.obsidian.enable;
        expected = true;
      }
    );

  };
}
