# Forward adapter guard evaluation design

## Status

Implemented.

## Supported pattern

Den supports a guarded custom-class forward that reads an independently defined target value:

```nix
gitClass =
  { class, aspect-chain }:
  den.batteries.forward {
    each = lib.singleton true;
    fromClass = _: "git";
    intoClass = _: "homeManager";
    intoPath = _: [ "programs" "git" ];
    fromAspect = _: lib.head aspect-chain;
    guard = { config, ... }: _: lib.mkIf config.programs.git.enable;
  };
```

The target configuration supplies `programs.git.enable`. The forward supplies values below `programs.git` after the guard resolves.

The guard reads the final target configuration. The value that the guard reads must not depend on the same guarded forward.

## Original failure

The old nested adapter staged the source below `config.den.fwd.<adapterKey>`. It evaluated that source with the target module arguments as `specialArgs`.

This process replaced the source evaluator's `config`, `options`, and `lib` arguments with target arguments. A context-aware source could receive the Home Manager configuration when it requested its own source configuration.

The staging evaluator also produced module metadata:

- `_module`
- `warnings`
- `assertions`

Context wrappers add a collision validator. This validator produces `warnings`, so context-aware sources made the metadata leak visible.

Static custom-class fragments can also carry Den aspect metadata. Nested aspect wrappers add `_`, `__provider`, `__contentValues`, and `__providesForwarded`.

When a guard applied `lib.mkIf`, Nix pushed the condition below the target path. A synthetic `_` functor then became an invalid option such as `programs.zed-editor._`.

The old dependency path was:

```text
evaluate a target option
  -> inspect the guarded contribution
    -> read config.den.fwd.<adapterKey>
      -> evaluate the source with target config
        -> re-enter the target fixpoint or expose evaluator metadata
```

A false guard could expose a nested conditional marker or recurse. An enabled guard could fail when a source module read source-local configuration.

## Implemented lifecycle

The nested adapter has three phases.

### 1. Evaluate the source

The adapter evaluates the source in a separate module system:

```nix
evaluated = lib.evalModules {
  specialArgs = sourceSpecialArgsFn args;
  modules = adapterMods ++ [ sourceModule ];
};
```

The source stays a module during evaluation. Imports, option declarations, priorities, defaults, module keys, and Den context wrappers keep their module semantics.

Implicit adaptation removes the target `config`, `options`, and `lib` arguments. The source evaluator supplies its own values for these names.

The adapter retains non-reserved target arguments, including values from `config._module.args`. Source modules can still request arguments such as `pkgs`.

### 2. Clean the routing value

The adapter removes evaluator metadata from `evaluated.config`. It cleans the source root and the selected target path.

The adapter also removes Den aspect metadata from marked wrapper attrsets. This cleanup is recursive because the aspect metadata can occur below source configuration keys.

The cleanup does not recurse into derivations or module-property contents. It also preserves an ordinary `_` key when its attrset has no Den metadata marker.

The cleaned value is routing data. Den does not place module-system metadata below the target option path.

### 3. Apply the target guard

The adapter nests the cleaned source below `intoPath`. It then applies the guard to the complete target contribution:

```nix
config = guardFn args (lib.setAttrByPath path forwarded);
```

This order keeps `lib.mkIf` at the module boundary. Den does not place `_type`, `condition`, or `content` below `programs.git`.

The guard still receives the target module arguments. As a result, it can read independently defined values from the final target configuration.

## Guard contract

Use a Boolean guard for structural tests:

```nix
guard = { options, ... }: options ? programs.git;
```

Den implements this form with `lib.optionalAttrs`. A false result emits no target definition.

Use a module transformer for configuration values:

```nix
guard = { config, ... }: _: lib.mkIf config.programs.git.enable;
```

The value read by this guard must have a definition outside the current forward. This contract includes ordinary target modules, defaults, and other independent definitions.

A self-dependent guard has normal Nix recursion semantics. Den does not create a target snapshot or subtract the current contribution from merged configuration.

## Adapter argument contract

If `adaptArgs` is absent, nested source evaluation preserves source-local `config`, `options`, and `lib`. It also passes non-reserved target module arguments to the source evaluator.

If `adaptArgs` is explicit, Den uses its result as `specialArgs`. This behavior preserves existing adapters such as `adaptArgs = lib.id`.

Use a named argument to give target configuration to a source module without replacing source-local `config`:

```nix
adaptArgs = { config, ... }: { osConfig = config; };
```

The source can then request both configurations:

```nix
{ config, osConfig, ... }:
{
  # config is the source configuration.
  # osConfig is the target configuration.
}
```

## Route ownership

The parent pipeline and a `host-aspects` spawn can see the same forward route. The parent owns nested complex adapter routes when both pipelines register the same identity.

Single ownership prevents duplicate source evaluation. It also prevents list values from appearing twice in the target configuration.

Top-level adapters keep their existing import path. Simple dynamic routes can still use `den.fwd` staging and keep declaration-based ownership.

## Regression coverage

`templates/ci/modules/deadbugs/forward-module-metadata.nix` keeps the documented Git class and tests enabled and disabled targets.

The fixture also includes the load-bearing shape from the original Zed failure:

- Global `host-aspects` registration.
- A context-aware source module.
- A source-local `config` read.
- Collision-validator metadata.
- A re-exported static nested custom-class fragment.
- Recursive Den aspect metadata.
- An ordinary target sibling definition.
- Exact checks for leaked module and conditional keys.

Other suites protect explicit `adaptArgs = lib.id`, named target aliases, dynamic paths, chained forwards, and single route ownership.

## Non-goals

- Den does not provide a pre-forward target snapshot.
- Den does not subtract values from merged target configuration.
- Den does not define results for self-dependent guards.
- Den does not special-case Git or Zed in the forwarding handler.
