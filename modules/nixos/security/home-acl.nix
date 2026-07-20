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
  policyNames = map (policy: policy.name) cfg.policies;
  cacheNames = [
    ".cache"
    "Cache"
    "Code Cache"
    "GPUCache"
    "CacheStorage"
    "CachedData"
    "DawnGraphiteCache"
  ];
  cacheNamesForPolicy = policy:
    if policy.access == "read-write"
    then []
    else cacheNames;
  excludedDirectoryNames = policy: cacheNamesForPolicy policy ++ policy.excludeDirectories;
  excludedDirectoryExpression = policy:
    concatStringsSep " -o " (map (name: "-name '${name}'") (excludedDirectoryNames policy));

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
  directoryPermissions = policy:
    if policy.access == "read-write"
    then "rwx"
    else "r-x";
  filePermissions = policy:
    if policy.access == "read-write"
    then "rw-"
    else "r-X";
  defaultPermissions = policy:
    if policy.access == "read-write"
    then "rwX"
    else "r-X";
  directoryAcl = policy:
    concatStringsSep "," (
      map (entry: "${entry}:${directoryPermissions policy}") (aclEntries policy)
      ++ ["m::${directoryPermissions policy}"]
      ++ map (entry: "d:${entry}:${defaultPermissions policy}") (aclEntries policy)
      ++ ["d:m::${defaultPermissions policy}"]
    );
  accessDirectoryAcl = policy:
    concatStringsSep "," (map (entry: "${entry}:${directoryPermissions policy}") (aclEntries policy) ++ ["m::${directoryPermissions policy}"]);
  traversalAcl = policy:
    concatStringsSep "," (map (entry: "${entry}:--x") (aclEntries policy));
  fileAcl = policy:
    concatStringsSep "," (map (entry: "${entry}:${filePermissions policy}") (aclEntries policy) ++ ["m::${filePermissions policy}"]);
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
    excludedNames = excludedDirectoryNames policy;
    excludedExpression = excludedDirectoryExpression policy;
  in
    pkgs.writeShellScript "home-acl-repair-subtree-${policy.name}" ''
      set -eu

      subtree="$1"
      find=${pkgs.findutils}/bin/find

      printf 'home ACL (${policy.name}): repairing %s\n' "$subtree"

      "$find" "$subtree" -xdev \
        ${lib.optionalString (excludedNames != []) ''\( -type d \( ${excludedExpression} \) -prune \) -o''} \
        -type d -exec ${applyDirectories} {} +
      "$find" "$subtree" -xdev \
        ${lib.optionalString (excludedNames != []) ''\( -type d \( ${excludedExpression} \) -prune \) -o''} \
        -type f -exec ${applyFiles} {} +
    '';

  mkRepairScript = policy: let
    home = targetHome policy;
    worker = mkWorker policy;
    applyFiles = mkApplyScript policy "files";
    excludedNames = excludedDirectoryNames policy;
    excludedExpression = excludedDirectoryExpression policy;
    principal =
      if policy.readerGroup == null
      then "user:${policy.reader}"
      else "group:${policy.readerGroup}";
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
              ${lib.optionalString (policy.access != "read-write") ''
                "$setfacl" -m 'm::--x' "$parent"
              ''}
              parent="$(${pkgs.coreutils}/bin/dirname "$parent")"
            done
            "$setfacl" -m '${directoryAcl policy}' "$subtree"
            ${worker} "$subtree"

            # Reapply only the parent traversal ACL after the subtree repair.
            # Read-write policies preserve existing parent ACL masks.
            parent="$(${pkgs.coreutils}/bin/dirname "$subtree")"
            while true; do
              "$setfacl" -m '${traversalAcl policy}' "$parent"
              ${lib.optionalString (policy.access != "read-write") ''
                if test "$parent" != "$home"; then
                  "$setfacl" -m 'm::--x' "$parent"
                fi
              ''}
              if test "$parent" = "$home"; then
                break
              fi
              parent="$(${pkgs.coreutils}/bin/dirname "$parent")"
            done
          fi
        ''
      )
      policy.paths;
    repairBody =
      if policy.paths != []
      then scopedRepair
      else ''
        # Apply the policy across the target home, honoring any declared exclusions.
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
          ${lib.optionalString (excludedNames != []) ''\( -type d \( ${excludedExpression} \) -prune \) -o''} \
          -type d -print0 | \
          "$xargs" -0 -r -n 1 -P 2 ${worker}
      '';
  in
    pkgs.writeShellScript "home-acl-repair-${policy.name}" ''
      set -eu

      home='${home}'
      setfacl=${pkgs.acl}/bin/setfacl
      getfacl=${pkgs.acl}/bin/getfacl
      grep=${pkgs.gnugrep}/bin/grep
      find=${pkgs.findutils}/bin/find
      xargs=${pkgs.findutils}/bin/xargs

      test -d "$home" || exit 0

      ${lib.optionalString (excludedNames != []) ''
        # Excluded directories may have inherited an ACL before their exclusion
        # was declared. Remove both access and default entries from their full tree.
        echo "home ACL (${policy.name}): removing stale ACLs from excluded directories"
        "$find" "$home" -xdev -type d \( ${excludedExpression} \) -prune \
          -exec "$setfacl" -R -x '${removeAcl policy}' {} + 2>/dev/null || true
        "$find" "$home" -xdev -type d \( ${excludedExpression} \) -prune \
          -exec "$setfacl" -R -x '${removeDefaultAcl policy}' {} + 2>/dev/null || true
      ''}

      ${repairBody}

      verify_acl() {
        path="$1"
        expected="$2"
        if ! "$getfacl" -cp "$path" | "$grep" -E -q "^$expected([[:space:]]|$)"; then
          echo "home ACL (${policy.name}): effective ACL mismatch on $path; expected $expected" >&2
          exit 1
        fi
      }

      ${lib.optionalString (policy.paths == [] && policy.access == "read-write") ''
        verify_acl "$home" '${principal}:rwx'
        verify_acl "$home" 'mask::rwx'
        for relative_path in .hermes .hermes/browser-profile .cache; do
          nested_path="$home/$relative_path"
          if test -d "$nested_path"; then
            verify_acl "$nested_path" '${principal}:rwx'
            verify_acl "$nested_path" 'mask::rwx'
          fi
        done
      ''}

      ${concatMapStringsSep "\n" (
          relativePath: ''
            scoped_path="$home/${relativePath}"
            if test -d "$scoped_path"; then
              verify_acl "$scoped_path" '${principal}:${directoryPermissions policy}'
              verify_acl "$scoped_path" 'mask::${directoryPermissions policy}'

              parent="$(${pkgs.coreutils}/bin/dirname "$scoped_path")"
              while test "$parent" != "$home"; do
                verify_acl "$parent" '${principal}:--x'
                ${lib.optionalString (policy.access != "read-write") ''
                  verify_acl "$parent" 'mask::--x'
                ''}
                parent="$(${pkgs.coreutils}/bin/dirname "$parent")"
              done
            fi
          ''
        )
        policy.paths}
      echo "home ACL (${policy.name}): repair complete"
    '';

  reconcileScript = pkgs.writeShellScript "home-acl-reconcile" ''
    set -eu

    lock=/run/lock/home-acl-reconcile.lock
    exec 9>"$lock"
    ${pkgs.util-linux}/bin/flock 9

    ${concatMapStringsSep "\n" (policy: ''
      echo "[${policy.name}] applying ACL policy"
      ${mkRepairScript policy}
    '') cfg.policies}
  '';

  statusCommand = pkgs.writeShellScriptBin "home-acl-status" ''
    set -eu
    systemctl=${pkgs.systemd}/bin/systemctl
    echo "Home ACL reconciliation:"
    echo "  service: $($systemctl is-active home-acl-reconcile.service 2>/dev/null || true)"
    echo "  timer: $($systemctl is-active home-acl-reconcile.timer 2>/dev/null || true)"
    echo "Policies:"
    ${concatMapStringsSep "\n" (policy: ''
        echo "  ${policy.name}: ${targetHome policy} -> ${policy.reader} (${policy.access})"
      '')
      cfg.policies}
  '';

  repairCommand = pkgs.writeShellScriptBin "hermes-repair-acls" ''
    set -eu
    systemctl=${pkgs.systemd}/bin/systemctl
    sudo=/run/wrappers/bin/sudo

    echo "Authenticating once for Hermes ACL repair..."
    "$sudo" -v

    echo "Starting home ACL reconciliation..."
    if "$sudo" -n "$systemctl" start home-acl-reconcile.service; then
      echo "Home ACL reconciliation complete"
    else
      status=$?
      echo "Home ACL reconciliation failed; showing current unit status"
      "$sudo" -n "$systemctl" status home-acl-reconcile.service --no-pager || true
      exit "$status"
    fi
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
                description = "Stable name used for policy reporting and deterministic reconciliation order.";
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
              access = mkOption {
                type = types.enum ["read-only" "read-write"];
                default = "read-only";
                description = "Permissions granted by this policy.";
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
          assertion = builtins.length policyNames == builtins.length (lib.unique policyNames);
          message = "services.homeAcl policy names must be unique.";
        }
      ];

    systemd.services.home-acl-reconcile = {
      description = "Reconcile configured home ACL policies";
      after = ["systemd-tmpfiles-resetup.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = reconcileScript;
        TimeoutStartSec = "45min";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.home-acl-reconcile = {
      description = "Reconcile configured home ACL policies periodically";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "6h";
        Persistent = true;
        Unit = "home-acl-reconcile.service";
      };
    };

    services.homeAcl.statusCommand = statusCommand;

    environment.systemPackages = [
      statusCommand
      repairCommand
    ];
  };
}
