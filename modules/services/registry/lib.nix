{
  ociImageReferencePattern = "[^[:space:]@]+:[A-Za-z0-9_][A-Za-z0-9_.-]*@sha256:[0-9a-f]{64}";

  mkService = {
    name,
    optionPath,
    enablePath ? optionPath ++ ["enable"],
    defaults ? {},
    local ? true,
    listeners ? {
      settingsTcpPorts =
        if defaults ? port
        then ["port"]
        else [];
    },
    firewall ? null,
    exposure ?
      if firewall == null || firewall == false
      then null
      else "loopback",
    containerPublished ? false,
    proxy ? null,
    homepage ? null,
    health ? null,
    dns ? proxy != null,
    ociImages ? {},
    secrets ? [],
    credentials ? [],
    api ? null,
    metrics ? null,
    backup ? null,
    setup ? null,
  }: let
    resolvedDefaults =
      defaults
      // (
        if defaults ? subdomain
        then {domain = "${defaults.subdomain}.home.arpa";}
        else {}
      );
  in {
    inherit
      name
      optionPath
      enablePath
      local
      listeners
      firewall
      exposure
      containerPublished
      proxy
      homepage
      health
      dns
      ociImages
      secrets
      credentials
      api
      metrics
      backup
      setup
      ;
    defaults = resolvedDefaults;
  };

  localProxy = {
    target = "loopback";
    scheme = "http";
  };

  card = section: order: title: icon: description: {
    inherit section order title icon description;
    hrefScheme = "https";
  };

  health = unit: {
    inherit unit;
    protocol = "http";
  };

  backup = directory: unit: owner: group: {
    inherit directory unit owner group;
    units = [unit];
    pathOption = ["paths" "dataDir"];
    extraPathOptions = [];
    database = null;
  };

  setup = group: order: presets: {
    inherit group order presets;
    presetControlled = true;
    requiresLan = true;
    suggestDocker = false;
    support = "Evaluation only; application restore unverified";
    requirements = "Plan persistent application storage and separate backups; see the service guide for sizing";
  };

  hostSetup = order: label: {
    group = "integration";
    inherit order label;
    presets = [];
    presetControlled = false;
    requiresLan = false;
    suggestDocker = false;
  };

  credential = {
    sops = label: path: {
      inherit label;
      source = {
        kind = "sops";
        inherit path;
      };
    };

    file = {
      label,
      path ? null,
      pathOption ? null,
      fallbackPathOption ? null,
      suffix ? "",
      envKey ? null,
      optional ? false,
    }: {
      inherit label;
      source = {
        kind = "file";
        inherit path pathOption fallbackPathOption suffix envKey optional;
      };
    };

    option = label: path: {
      inherit label;
      source = {
        kind = "option";
        inherit path;
      };
    };

    literal = label: value: warning: {
      inherit label;
      source = {
        kind = "literal";
        inherit value warning;
      };
    };

    manual = message: {
      label = "setup";
      source = {
        kind = "manual";
        inherit message;
      };
    };
  };
}
