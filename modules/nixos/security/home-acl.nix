{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    concatMap
    concatMapStringsSep
    concatStringsSep
    mkIf
    mkOption
    types
    ;

  cfg = config.services.homeAcl;
  cacheNames = [
    ".cache"
    "Cache"
    "Code Cache"
    "GPUCache"
    "CacheStorage"
    "CachedData"
    "DawnGraphiteCache"
  ];
  cacheNameExpression = concatStringsSep " -o " (map (name: "-name '${name}'") cacheNames);

  unitName = policy: "${policy.name}-acl";
  unitNames = map unitName cfg.policies;

  isSafeIdentity = name: builtins.match "[a-z_][a-z0-9_-]*" name != null;
  targetHome = policy: lib.attrByPath [policy.target "home"] "/nonexistent" config.users.users;
  readerIsGroupMember = policy:
    policy.readerGroup
    == null
    || (
      builtins.hasAttr policy.readerGroup config.users.groups
      && (
        lib.elem policy.reader (config.users.groups.${policy.readerGroup}.members or [])
        || lib.elem policy.readerGroup (config.users.users.${policy.reader}.extraGroups or [])
        || config.users.users.${policy.reader}.group == policy.readerGroup
      )
    );
  aclEntries = policy:
    if policy.readerGroup == null
    then ["u:${policy.reader}"]
    else ["g:${policy.readerGroup}"];
  directoryAcl = policy:
    concatStringsSep "," (
      map (entry: "${entry}:r-x") (aclEntries policy)
      ++ ["m::r-x"]
      ++ map (entry: "d:${entry}:r-X") (aclEntries policy)
      ++ ["d:m::r-X"]
    );
  accessDirectoryAcl = policy:
    concatStringsSep "," (map (entry: "${entry}:r-x") (aclEntries policy) ++ ["m::r-x"]);
  traversalAcl = policy:
    concatStringsSep "," (map (entry: "${entry}:--x") (aclEntries policy) ++ ["m::--x"]);
  fileAcl = policy:
    concatStringsSep "," (map (entry: "${entry}:r-X") (aclEntries policy) ++ ["m::r-X"]);
  removeAcl = policy: concatStringsSep "," (aclEntries policy);
  removeDefaultAcl = policy: concatStringsSep "," (map (entry: "d:${entry}") (aclEntries policy));

  mkApplyScript = policy: mode:
    pkgs.writeShellScript "home-acl-apply-${policy.name}-${mode}" ''
      set -eu

      acl_mode='${
        if mode == "directories"
        then directoryAcl policy
        else fileAcl policy
      }'
      setfacl=${pkgs.acl}/bin/setfacl

      if "$setfacl" -m "$acl_mode" "$@" 2>/dev/null; then
        exit 0
      fi

      status=0
      for path do
        if test -e "$path" && ! "$setfacl" -m "$acl_mode" "$path" 2>/dev/null; then
          status=1
        fi
      done
      exit "$status"
    '';

  mkWorker = policy: let
    applyDirectories = mkApplyScript policy "directories";
    applyFiles = mkApplyScript policy "files";
    excludedDirectoryNames = cacheNames ++ policy.excludeDirectories;
    excludedDirectoryExpression = concatStringsSep " -o " (map (name: "-name '${name}'") excludedDirectoryNames);
  in
    pkgs.writeShellScript "home-acl-repair-subtree-${policy.name}" ''
      set -eu

      subtree="$1"
      find=${pkgs.findutils}/bin/find

      printf 'home ACL (${policy.name}): repairing %s\n' "$subtree"

      "$find" "$subtree" -xdev \
        \( -type d \( ${excludedDirectoryExpression} \) -prune \) -o \
        -type d -exec ${applyDirectories} {} +
      "$find" "$subtree" -xdev \
        \( -type d \( ${excludedDirectoryExpression} \) -prune \) -o \
        -type f -exec ${applyFiles} {} +
    '';

  mkRepairScript = policy: let
    home = targetHome policy;
    worker = mkWorker policy;
    applyFiles = mkApplyScript policy "files";
    excludedDirectoryNames = cacheNames ++ policy.excludeDirectories;
    excludedDirectoryExpression = concatStringsSep " -o " (map (name: "-name '${name}'") excludedDirectoryNames);
    scopedRepair =
      concatMapStringsSep "\n" (
        relativePath: let
          root = builtins.head (lib.splitString "/" relativePath);
        in ''
          subtree="$home/${relativePath}"
          if test -d "$subtree"; then
            echo "home ACL (${policy.name}): repairing scoped subtree $subtree"
            # Remove stale broad-policy entries from the protected root before
            # applying the intentionally narrow subtree ACL below.
            "$setfacl" -R -x '${removeAcl policy}' "$home/${root}" 2>/dev/null || true
            "$setfacl" -R -x '${removeDefaultAcl policy}' "$home/${root}" 2>/dev/null || true

            parent="$subtree"
            while test "$parent" != "$home"; do
              "$setfacl" -m '${traversalAcl policy}' "$parent"
              parent="$(${pkgs.coreutils}/bin/dirname "$parent")"
            done
            "$setfacl" -m '${directoryAcl policy}' "$subtree"
            ${worker} "$subtree"
          fi
        ''
      )
      policy.paths;
    repairBody =
      if policy.paths != []
      then scopedRepair
      else ''
        # Excluded top-level trees remain private and are not traversed.
        echo "home ACL (${policy.name}): applying inherited directory ACLs"
        "$setfacl" -m '${
          if policy.excludeDirectories == []
          then directoryAcl policy
          else accessDirectoryAcl policy
        }' "$home"

        echo "home ACL (${policy.name}): repairing files directly under $home"
        "$find" "$home" -xdev -mindepth 1 -maxdepth 1 -type f \
          -exec ${applyFiles} {} +
        echo "home ACL (${policy.name}): repairing top-level subtrees with two workers"
        "$find" "$home" -xdev -mindepth 1 -maxdepth 1 \
          \( -type d \( ${excludedDirectoryExpression} \) -prune \) -o \
          -type d -print0 | \
          "$xargs" -0 -r -n 1 -P 2 ${worker}
      '';
  in
    pkgs.writeShellScript "home-acl-repair-${policy.name}" ''
      set -eu

      home='${home}'
      setfacl=${pkgs.acl}/bin/setfacl
      find=${pkgs.findutils}/bin/find
      xargs=${pkgs.findutils}/bin/xargs
      lock=/run/lock/home-acl-${policy.name}.lock

      test -d "$home" || exit 0
      exec 9>"$lock"
      ${pkgs.util-linux}/bin/flock 9

      # Excluded caches may have inherited an ACL before their exclusion was
      # declared. Remove both access and default entries from their full tree.
      echo "home ACL (${policy.name}): removing stale ACLs from excluded caches"
      "$find" "$home" -xdev -type d \( ${cacheNameExpression} \) -prune \
        -exec "$setfacl" -R -x '${removeAcl policy}' {} + 2>/dev/null || true
      "$find" "$home" -xdev -type d \( ${cacheNameExpression} \) -prune \
        -exec "$setfacl" -R -x '${removeDefaultAcl policy}' {} + 2>/dev/null || true

      ${repairBody}
      echo "home ACL (${policy.name}): repair complete"
    '';

  statusCommand = pkgs.writeShellScriptBin "home-acl-status" ''
    set -eu
    systemctl=${pkgs.systemd}/bin/systemctl
    echo "Home ACL policies:"
    ${concatMapStringsSep "\n" (policy: ''
        echo "  ${policy.name}: ${targetHome policy} -> ${policy.reader}"
        echo "    service: $($systemctl is-active ${unitName policy}.service 2>/dev/null || true)"
        echo "    timer: $($systemctl is-active ${unitName policy}.timer 2>/dev/null || true)"
      '')
      cfg.policies}
  '';

  repairCommand = pkgs.writeShellScriptBin "hermes-repair-acls" ''
    set -eu
    systemctl=${pkgs.systemd}/bin/systemctl
    journalctl=${pkgs.systemd}/bin/journalctl
    sudo=/run/wrappers/bin/sudo

    echo "Authenticating once for Hermes ACL repair..."
    "$sudo" -v

    run_policy() {
      policy_name="$1"
      unit="$2"

      echo "[$policy_name] starting $unit; progress follows"
      "$sudo" -n "$journalctl" --no-pager -n 0 -f -u "$unit" &
      journal_pid=$!

      cleanup_journal() {
        kill "$journal_pid" 2>/dev/null || true
        wait "$journal_pid" 2>/dev/null || true
      }

      if "$sudo" -n "$systemctl" start "$unit"; then
        cleanup_journal
        echo "[$policy_name] complete"
      else
        status=$?
        cleanup_journal
        echo "[$policy_name] failed; showing current unit status"
        "$sudo" -n "$systemctl" status "$unit" --no-pager || true
        return "$status"
      fi
    }

    ${concatMapStringsSep "\n" (
        policy: ''run_policy "${policy.name}" "${unitName policy}.service"''
      )
      cfg.policies}
  '';
in {
  options.services.homeAcl = {
    policies = mkOption {
      type = types.listOf (
        types.submodule (
          {...}: {
            options = {
              name = mkOption {
                type = types.str;
                description = "Stable name used for the generated systemd service and timer.";
              };
              reader = mkOption {
                type = types.str;
                description = "User granted read/search/execute access.";
              };
              target = mkOption {
                type = types.str;
                description = "User whose configured home directory receives the ACL.";
              };
              readerGroup = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Optional group used as the ACL principal instead of the reader user.";
              };
              paths = mkOption {
                type = types.listOf types.str;
                default = [];
                description = "Relative target-home subtrees to repair instead of the entire home.";
              };
              excludeDirectories = mkOption {
                type = types.listOf types.str;
                default = [];
                description = "Directory names excluded from broad ACL repair.";
              };
            };
          }
        )
      );
      default = [];
      description = "Explicit cross-home read-only ACL policies.";
    };

    policyUnits = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      internal = true;
      description = "Generated ACL repair systemd unit names.";
    };

    statusCommand = mkOption {
      type = types.package;
      readOnly = true;
      internal = true;
      description = "Generated command reporting home ACL policy status.";
    };
  };

  config = mkIf (cfg.policies != []) {
    assertions =
      concatMap (policy: [
        {
          assertion = builtins.hasAttr policy.reader config.users.users;
          message = "services.homeAcl policy '${policy.name}' references missing reader '${policy.reader}'.";
        }
        {
          assertion = builtins.hasAttr policy.target config.users.users;
          message = "services.homeAcl policy '${policy.name}' references missing target '${policy.target}'.";
        }
        {
          assertion = policy.readerGroup == null || builtins.hasAttr policy.readerGroup config.users.groups;
          message = "services.homeAcl policy '${policy.name}' references a missing ACL group.";
        }
        {
          assertion = readerIsGroupMember policy;
          message = "services.homeAcl policy '${policy.name}' reader '${policy.reader}' is not a member of its ACL group.";
        }
        {
          assertion = policy.reader != policy.target;
          message = "services.homeAcl policy '${policy.name}' must not grant a user access to their own home.";
        }
        {
          assertion = builtins.match "[A-Za-z0-9][A-Za-z0-9_-]*" policy.name != null;
          message = "services.homeAcl policy '${policy.name}' must use a systemd-safe name.";
        }
        {
          assertion = isSafeIdentity policy.reader && isSafeIdentity policy.target;
          message = "services.homeAcl policy '${policy.name}' user names must be safe system identities.";
        }
        {
          assertion = policy.readerGroup == null || isSafeIdentity policy.readerGroup;
          message = "services.homeAcl policy '${policy.name}' ACL group must be a safe system identity.";
        }
        {
          assertion = lib.hasPrefix "/" (targetHome policy);
          message = "services.homeAcl policy '${policy.name}' target home must be an absolute path.";
        }
        {
          assertion = lib.all (path: builtins.match "[A-Za-z0-9._/-]+" path != null && !(lib.hasPrefix "/" path) && !(builtins.elem ".." (lib.splitString "/" path))) policy.paths;
          message = "services.homeAcl policy '${policy.name}' paths must be safe relative paths.";
        }
        {
          assertion = lib.all (name: builtins.match "[A-Za-z0-9._ -]+" name != null) policy.excludeDirectories;
          message = "services.homeAcl policy '${policy.name}' excluded directory names contain unsafe characters.";
        }
      ])
      cfg.policies
      ++ [
        {
          assertion = builtins.length unitNames == builtins.length (lib.unique unitNames);
          message = "services.homeAcl policy names must be unique.";
        }
      ];

    systemd.services = lib.listToAttrs (
      map (policy: {
        name = unitName policy;
        value = {
          description = "Grant ${policy.reader} read-only access to ${policy.target}'s home";
          restartIfChanged = false;
          stopIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = mkRepairScript policy;
            TimeoutStartSec = "45min";
            Nice = 10;
            IOSchedulingClass = "idle";
          };
        };
      })
      cfg.policies
    );

    systemd.timers = lib.listToAttrs (
      map (policy: {
        name = unitName policy;
        value = {
          description = "Refresh ${policy.reader}'s read-only access to ${policy.target}'s home";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "10min";
            OnUnitActiveSec = "6h";
            Unit = "${unitName policy}.service";
          };
        };
      })
      cfg.policies
    );

    services.homeAcl.policyUnits = map (name: "${name}.service") unitNames;
    services.homeAcl.statusCommand = statusCommand;

    environment.systemPackages = [
      statusCommand
      repairCommand
    ];
  };
}
