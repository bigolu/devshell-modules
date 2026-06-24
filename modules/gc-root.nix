# - You can perform filtering on your roots which would be hard to do with
#   nix-direnv. For example, filtering your npins' pins based on which platforms they
#   apply to. This way, a macOS only pin won't have a GC root on Linux.
# - The option to show a diff of your dev shell when it changes. This useful for
#   verifying that a refactor doesn't change the dev shell or just seeing what has
#   changed.
# - Roots are joined into a single derivation so you'll only have a single GC root
#   per project. This is reduces noise in the full list of GC roots for your system
#   (/nix/var/nix/gcroots/auto).

{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (builtins) elem;
  inherit (lib)
    optionalAttrs
    mkOption
    types
    getExe'
    escapeShellArg
    pipe
    isStorePath
    attrsToList
    concatMap
    getExe
    mapAttrsToList
    optionalString
    genericClosure
    concatLines
    filter
    filterAttrs
    id
    ;
  gcRootConfig = config.gcRoot;
in
{
  options.gcRoot = {
    enable = mkOption {
      default = true;
      example = true;
      description = "Whether to enable the creation of a GC root for the devshell.";
      type = types.bool;
    };

    path = mkOption {
      type = types.str;
      description = "Path for GC root, relative to `$PRJ_DATA_DIR`";
      default = "gc-roots/${config.devshell.name}";
      apply = value: ''"$PRJ_DATA_DIR"/${escapeShellArg value}'';
    };

    diff = {
      enable = mkOption {
        default = true;
        example = true;
        description = "Whether to show a diff when replacing an old GC root.";
        type = types.bool;
      };
    };

    roots = {
      paths = mkOption {
        type = types.listOf types.package;
        description = "A list of store paths to include in the GC root.";
        default = [ ];
      };

      flake = {
        inputs = mkOption {
          type = types.attrs;
          description = "An attrset of flake inputs to include in the GC root.";
          default = { };
        };

        exclude = mkOption {
          type = types.listOf types.str;
          description = "The names of the direct inputs to exclude from the GC root. We take strings so we can determine if an input should be excluded just by its name, i.e. the key in the `inputs` set. This way, we can avoid fetching an excluded input and its transitive inputs. This is the reason we only allow direct inputs to be excluded.";
          default = [ ];
        };
      };
    };
  };

  config.devshell.startup = optionalAttrs gcRootConfig.enable {
    gcRoot.text =
      let
        inherit (pkgs) writeText dix coreutils;

        handlers = {
          paths = id;

          # There's an issue for having flakes retain a reference to their inputs[1].
          #
          # [1]: https://github.com/NixOS/nix/issues/6895
          flake =
            let
              getInputsClosure =
                {
                  inputs,
                  exclude,
                }:
                let
                  # We don't want to make a GC root for self
                  removeExcluded = filterAttrs (name: _input: (name != "self") && (!(elem name exclude)));
                  toClosureNodes = mapAttrsToList (
                    # Used by `genericClosure` for equality checks
                    _name: input: input // { key = input.outPath; }
                  );
                in
                genericClosure {
                  startSet = pipe inputs [
                    removeExcluded
                    toClosureNodes
                  ];
                  operator =
                    input:
                    toClosureNodes (
                      filterAttrs
                        # We don't want to make a GC root for self.
                        (_name: input: input.outPath != inputs.self.outPath)
                        # Non-Flake inputs will not have inputs.
                        (input.inputs or { })
                    );
                };
            in
            config:
            pipe config [
              getInputsClosure
              # If these inputs came from `lix/flake-compat` and `copySourceTreeToStore`
              # is false, then the outPath any direct inputs of type "path" will not be a
              # store path.
              (filter isStorePath)
            ];
        };

        rootsFile = pipe gcRootConfig.roots [
          attrsToList
          (concatMap ({ name, value }: handlers.${name} value))
          (rootsList: writeText "roots.txt" (concatLines rootsList))
        ];

        dixExe = getExe dix;
        ln = getExe' coreutils "ln";
        realpath = getExe' coreutils "realpath";
        mkdir = getExe' coreutils "mkdir";
        tail = getExe' coreutils "tail";
        touch = getExe' coreutils "touch";
        mktemp = getExe' coreutils "mktemp";
        rm = getExe' coreutils "rm";
        mv = getExe' coreutils "mv";

        shellGcRoot = "${gcRootConfig.path}/shell-gc-root";
        shellToDiff = "${gcRootConfig.path}/shell-to-diff";
        shellStorePathPrefix = "${gcRootConfig.path}/shell-store-path";
      in
      ''
        # The path to the GC roots file is included here to make it part
        # of the dev shell closure: ${rootsFile}

        # If the nix store doesn't have the devshell, assume `nix bundle` was
        # used. If `nix bundle` was used, we shouldn't do anything.
        if nix-store --query --hash "$DEVSHELL_DIR"" >/dev/null 2>&1; then
          if [[ ! -e ${gcRootConfig.path} ]]; then
            ${mkdir} --parents ${gcRootConfig.path}
          fi

          # TODO: `$DEVSHELL_DIR` is not the top-level derivation for
          # the dev shell. We use this command to find it. Ideally,
          # devshell would set an environment variable that contains the
          # path to the top-level derivation.
          shell_store_path=${shellStorePathPrefix}"''${DEVSHELL_DIR//\//-}"
          if [[ -e "$shell_store_path" ]]; then
            new_shell="$(<"$shell_store_path")"
          else
            new_shell="$(
              nix-store --query --referrers-closure "$DEVSHELL_DIR" |
                ${tail} --lines 1
            )"

            # PERF: Cache the shell store path
            #
            # Remove the old cached path.
            # Add `--force` to avoid race condition between multiple direnv instances
            ${rm} --force ${shellStorePathPrefix}*
            # Create the file this way for atomicity to avoid race condition
            # between multiple direnv instances
            temp="$(${mktemp})"
            echo "$new_shell" >"$temp"
            ${mv} --force "$temp" "$shell_store_path"
          fi

          ${optionalString gcRootConfig.diff.enable ''
            # If a terminal and IDE run this at the same time, which can
            # happen if you use direnv and vscode-direnv with auto-reload
            # enabled, the diff will only be printed by the process that
            # updates the GC root. To ensure the diff is shown in the
            # terminal, we store a separate symlink to the dev shell
            # that's only updated if stdout is connected to a terminal.
            if [[ ( ! ${shellToDiff} -ef "$new_shell" ) && -t 1 ]]; then
              if [[ -e ${shellToDiff} ]]; then
                ${dixExe} "$(${realpath} ${shellToDiff})" "$new_shell"
              fi
              ${ln} --force --no-dereference --symbolic "$new_shell" ${shellToDiff}
            fi
          ''}

          if [[ ! ${shellGcRoot} -ef "$new_shell" ]]; then
            nix-store --add-root ${shellGcRoot} --realise "$new_shell" >/dev/null
          else
            # `nh`[1] and `nix-sweep`[2] can delete GC roots that haven't been
            # modified in a certain amount of time. To avoid having this
            # GC root get deleted, we'll update the modification time.
            #
            # [1]: https://github.com/nix-community/nh
            # [2]: https://github.com/jzbor/nix-sweep
            ${touch} --no-dereference ${shellGcRoot}
          fi
        fi
      '';
  };
}
