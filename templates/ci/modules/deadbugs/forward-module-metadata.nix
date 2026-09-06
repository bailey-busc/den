# Regression: a guarded custom-class forward must deliver context-aware class
# settings into an existing Home Manager option path without exposing module
# metadata from the source evaluator.
{ denTest, ... }:
let
  gitClass =
    den: lib:
    { class, aspect-chain }:
    den.batteries.forward {
      each = lib.singleton true;
      fromClass = _: "git";
      intoClass = _: "homeManager";
      intoPath = _: [
        "programs"
        "git"
      ];
      fromAspect = _: lib.head aspect-chain;
      guard = { config, ... }: _: lib.mkIf config.programs.git.enable;
    };

  gitEnvironment = enabled: {
    homeManager.programs.git = {
      enable = enabled;
      settings.user.name = "Bailey";
    };

    git =
      { config, host, ... }:
      {
        settings.den = {
          _ = "kept";
          sourceHost = host.name;
        };
        settings.user = {
          email = "root@linux.com";
          signingKey = config.settings.den.sourceHost;
        };
      };
  };

  metadataKeys = [
    "_"
    "_module"
    "__contentValues"
    "__provider"
    "__providesForwarded"
    "warnings"
    "assertions"
    "_type"
    "condition"
    "content"
  ];
in
{
  flake.tests.deadbugs.forward-module-metadata = {
    # This follows Den's documented Git-class example.
    test-enabled-git-class-forwards-settings = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          den._.host-aspects
          (gitClass den lib)
        ];
        den.aspects.git-fragments.c.git.settings.alias.c = "status";
        # A function re-export of a static nested custom-class fragment carries
        # Den's synthetic `_` and `__provider` wrapper into source evaluation.
        den.aspects.forwarded-fragments.git = { ... }: den.aspects.git-fragments.c.git;
        den.aspects.git-environment = gitEnvironment true;
        den.aspects.tux.includes = [
          den.aspects.git-environment
          den.aspects.forwarded-fragments
        ];

        expr = {
          cAlias = tuxHm.programs.git.settings.alias.c;
          email = tuxHm.programs.git.settings.user.email;
          sourceHost = tuxHm.programs.git.settings.den.sourceHost;
          signingKey = tuxHm.programs.git.settings.user.signingKey;
          targetName = tuxHm.programs.git.settings.user.name;
          userUnderscore = tuxHm.programs.git.settings.den._;
          leakedKeys = builtins.filter (key: builtins.hasAttr key tuxHm.programs.git) metadataKeys;
          leakedSettingsKeys = builtins.filter (
            key: builtins.hasAttr key tuxHm.programs.git.settings
          ) metadataKeys;
          leakedAliasKeys = builtins.filter (
            key: builtins.hasAttr key tuxHm.programs.git.settings.alias
          ) metadataKeys;
        };
        expected = {
          cAlias = "status";
          email = "root@linux.com";
          sourceHost = "igloo";
          signingKey = "igloo";
          targetName = "Bailey";
          userUnderscore = "kept";
          leakedKeys = [ ];
          leakedSettingsKeys = [ ];
          leakedAliasKeys = [ ];
        };
      }
    );

    test-disabled-git-class-omits-settings = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          den._.host-aspects
          (gitClass den lib)
        ];
        den.aspects.git-fragments = {
          c.git.settings.alias.c = "status";
        };
        # Match the enabled source shape so the false guard must discard the
        # cleaned wrapper as one module-level conditional.
        den.aspects.forwarded-fragments.git = { ... }: den.aspects.git-fragments.c.git;
        den.aspects.git-environment = gitEnvironment false;
        den.aspects.tux.includes = [
          den.aspects.git-environment
          den.aspects.forwarded-fragments
        ];

        expr = {
          cAlias = tuxHm.programs.git.settings.alias.c or null;
          email = tuxHm.programs.git.settings.user.email or null;
          sourceHost = tuxHm.programs.git.settings.den.sourceHost or null;
          signingKey = tuxHm.programs.git.settings.user.signingKey or null;
          targetName = tuxHm.programs.git.settings.user.name;
          userUnderscore = tuxHm.programs.git.settings.den._ or null;
          leakedKeys = builtins.filter (key: builtins.hasAttr key tuxHm.programs.git) metadataKeys;
          leakedSettingsKeys = builtins.filter (
            key: builtins.hasAttr key tuxHm.programs.git.settings
          ) metadataKeys;
        };
        expected = {
          cAlias = null;
          email = null;
          sourceHost = null;
          signingKey = null;
          targetName = "Bailey";
          userUnderscore = null;
          leakedKeys = [ ];
          leakedSettingsKeys = [ ];
        };
      }
    );
  };
}
