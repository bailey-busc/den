{
  lib,
  ...
}:
let
  mkDirectAspect =
    {
      intoClass,
      staticIntoPath,
      evalConfig,
      freeformMod,
    }:
    sourceModule:
    if evalConfig then
      let
        evaluated = lib.evalModules {
          modules = [
            freeformMod
            sourceModule
          ];
        };
      in
      {
        ${intoClass} = lib.setAttrByPath staticIntoPath (
          builtins.removeAttrs evaluated.config [
            "_module"
            "warnings"
            "assertions"
          ]
        );
      }
    else
      {
        ${intoClass} = lib.setAttrByPath staticIntoPath (_: {
          imports = [ sourceModule ];
        });
        meta.contextDependent = true;
      };

  mkAdapterAspect =
    {
      intoClass,
      guardFn,
      guardArgs,
      intoPathArgs,
      intoPathFn,
      sourceSpecialArgsFn,
      adaptArgv,
      adapterMods,
    }:
    sourceModule: {
      meta.contextDependent = true;
      ${intoClass} = {
        __functionArgs = guardArgs // intoPathArgs // adaptArgv;
        __functor =
          _: args:
          let
            stripEvaluatorMetadata =
              value:
              if builtins.isAttrs value then
                builtins.removeAttrs value [
                  "_module"
                  "warnings"
                  "assertions"
                ]
              else
                value;
            stripAspectMetadata =
              value:
              if builtins.isAttrs value then
                let
                  # Static custom-class fragments can carry nested aspect
                  # wrappers. Remove their routing metadata without touching an
                  # ordinary `_` key in unmarked target data.
                  hasAspectMetadata = value ? __provider || value ? __contentValues || value ? __providesForwarded;
                  cleaned = builtins.removeAttrs value (
                    [
                      "__contentValues"
                      "__provider"
                      "__providesForwarded"
                    ]
                    ++ lib.optional hasAspectMetadata "_"
                  );
                in
                if value ? _type || lib.isDerivation value then
                  cleaned
                else
                  lib.mapAttrs (_: stripAspectMetadata) cleaned
              else
                value;
            stripRoutingMetadata = value: stripAspectMetadata (stripEvaluatorMetadata value);
            stripAtPath =
              path: value:
              if path == [ ] then
                stripRoutingMetadata value
              else if builtins.isAttrs value && value ? ${builtins.head path} then
                value
                // {
                  ${builtins.head path} = stripAtPath (builtins.tail path) value.${builtins.head path};
                }
              else
                value;
            path = intoPathFn args;
            evaluated = lib.evalModules {
              specialArgs = sourceSpecialArgsFn args;
              modules = adapterMods ++ [ sourceModule ];
            };
            forwarded = stripAtPath path (stripRoutingMetadata evaluated.config);
          in
          {
            config = guardFn args (lib.setAttrByPath path forwarded);
          };
      };
    };

  guardTree =
    guard: outerArgs: node:
    if builtins.isAttrs node && node ? imports then
      { imports = map (guardTree guard outerArgs) node.imports; }
    else
      _modArgs: {
        config = guard (if lib.isFunction node then node outerArgs else node);
      };

  evalImport =
    {
      adapterMods,
      sourceModule,
      extraArgsFor,
      guardFn,
    }:
    args:
    let
      extraArgs = extraArgsFor args;
      specialArgs =
        builtins.removeAttrs args [
          "config"
          "options"
          "lib"
        ]
        // extraArgs;
      evaluated = lib.evalModules {
        inherit specialArgs;
        modules = adapterMods ++ [
          sourceModule
        ];
      };
    in
    guardFn args evaluated.config;

  mkTopLevelAdapterAspect =
    {
      intoClass,
      guardFn,
      guardArgs,
      extraArgsFor,
      canDirectImport,
      adapterMods,
    }:
    sourceModule: {
      meta.contextDependent = true;
      ${intoClass} = {
        __functionArgs = guardArgs;
        __functor =
          _: args:
          let
            fullArgs = args // extraArgsFor args;
          in
          if canDirectImport then
            {
              imports = [ (guardTree (guardFn args) fullArgs sourceModule) ];
            }
          else
            evalImport {
              inherit
                adapterMods
                sourceModule
                extraArgsFor
                guardFn
                ;
            } args;
      };
    };

  # Build the same aspect shape the old forwardItem produced,
  # but with sourceModule resolved using the parent pipeline's context.
  buildForwardAspect =
    spec: sourceModule:
    let
      base = {
        includes = [ ];
        meta = { };
      };
      body =
        if spec.needsTopLevelAdapter then
          mkTopLevelAdapterAspect {
            inherit (spec)
              intoClass
              guardFn
              guardArgs
              extraArgsFor
              canDirectImport
              adapterMods
              ;
          } sourceModule
        else if spec.needsAdapter then
          mkAdapterAspect {
            inherit (spec)
              intoClass
              guardFn
              guardArgs
              intoPathArgs
              intoPathFn
              sourceSpecialArgsFn
              adaptArgv
              adapterMods
              ;
          } sourceModule
        else
          mkDirectAspect {
            inherit (spec)
              intoClass
              staticIntoPath
              evalConfig
              freeformMod
              ;
          } sourceModule;
    in
    base // body;

in
{
  inherit buildForwardAspect;
}
