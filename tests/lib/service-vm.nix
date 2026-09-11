{
  pkgs,
  publicModules,
}: {
  id,
  phase,
  module,
  node,
  script,
}: let
  tools = import ../../scripts/package.nix {inherit pkgs;};
in
  pkgs.testers.runNixOSTest {
    name = "nixstead-${id}-${phase}";
    node.pkgsReadOnly = false;
    requiredFeatures.kvm = false;
    nodes.machine = {
      config,
      lib,
      ...
    }: {
      imports = [publicModules.${module} node];
      system.stateVersion = "26.05";
      environment.systemPackages =
        [
          pkgs.curl
          pkgs.jq
        ]
        ++ lib.optionals (phase == "recovery") [
          pkgs.borgbackup
          tools.commands.backup-service-configs
          tools.commands.restore-service-configs
        ];
      environment.etc = lib.optionalAttrs (phase == "recovery") {
        "backup-registry.json".text = builtins.toJSON {
          ${id} = config.nixstead.serviceRegistry.${id};
        };
      };
      virtualisation.diskSize = lib.mkDefault 8192;
      virtualisation.memorySize = lib.mkDefault 3072;
    };
    testScript = ''
      import runpy
      ServiceScenario = runpy.run_path(${builtins.toJSON "${./service_scenario.py}"})["ServiceScenario"]
      phase = ${builtins.toJSON phase}
      start_all()
      ${builtins.readFile script}
    '';
  }
